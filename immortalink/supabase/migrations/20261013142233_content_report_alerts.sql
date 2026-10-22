-- Email is asynchronous: a provider outage must not prevent a safety report.
create table content_safety.alert_config (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  worker_token_hash text check (worker_token_hash ~ '^[a-f0-9]{64}$'),
  budget_day date not null default (now() at time zone 'UTC')::date,
  attempts_today integer not null default 0 check (attempts_today >= 0),
  daily_attempt_limit integer not null default 40 check (daily_attempt_limit between 1 and 100)
);
insert into content_safety.alert_config(singleton) values(true);

create table content_safety.report_alerts (
  report_id uuid primary key references public.content_reports(id) on delete cascade,
  state text not null default 'pending' check (state in ('pending','sending','sent','failed','skipped')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  created_at timestamptz not null default now(),
  first_attempt_at timestamptz,
  next_attempt_at timestamptz not null default now(),
  lease_id uuid,
  lease_until timestamptz,
  provider_id uuid,
  accepted_at timestamptz,
  result_code text
);
create index report_alerts_pending_idx on content_safety.report_alerts(next_attempt_at,created_at)
  where state in ('pending','sending');
alter table content_safety.alert_config enable row level security;
alter table content_safety.report_alerts enable row level security;
revoke all on content_safety.alert_config,content_safety.report_alerts from public,anon,authenticated;
grant all on content_safety.alert_config,content_safety.report_alerts to service_role;

create function content_safety.queue_report_alert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into content_safety.report_alerts(report_id) values(new.id) on conflict do nothing;
  return new;
end;
$$;
revoke all on function content_safety.queue_report_alert() from public,anon,authenticated;
create trigger queue_report_alert after insert on public.content_reports
  for each row execute function content_safety.queue_report_alert();
insert into content_safety.report_alerts(report_id)
  select id from public.content_reports where status in ('open','reviewing') on conflict do nothing;

create function public.claim_content_report_alert(p_worker_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg content_safety.alert_config; item content_safety.report_alerts;
begin
  select * into cfg from content_safety.alert_config where singleton for update;
  if p_worker_token is null or length(p_worker_token)<>64 or cfg.worker_token_hash is null
    or encode(sha256(convert_to(p_worker_token,'UTF8')),'hex')<>cfg.worker_token_hash then
    raise exception 'ALERT_WORKER_UNAUTHORIZED' using errcode='42501';
  end if;
  if not cfg.enabled then return null; end if;
  if cfg.budget_day <> (now() at time zone 'UTC')::date then
    update content_safety.alert_config set budget_day=(now() at time zone 'UTC')::date,attempts_today=0 where singleton;
    cfg.attempts_today:=0;
  end if;

  -- Resend keeps idempotency keys for 24h. Stop automatic recovery before that
  -- window closes, including a crash after provider acceptance but before ack.
  update content_safety.report_alerts set state='failed',result_code='REVIEW_REQUIRED',lease_id=null,lease_until=null
    where state in ('pending','sending') and (lease_until is null or lease_until < now())
      and (attempts>=5 or first_attempt_at < now()-interval '23 hours');
  update content_safety.report_alerts a set state='skipped',result_code='REPORT_CLOSED'
    where a.state='pending' and a.attempts=0 and exists(select 1 from public.content_reports r
      where r.id=a.report_id and r.status not in ('open','reviewing'));
  if cfg.attempts_today >= cfg.daily_attempt_limit then return null; end if;
  select * into item from content_safety.report_alerts
    where (state='pending' and next_attempt_at<=now()) or (state='sending' and lease_until<now())
    order by created_at limit 1 for update skip locked;
  if not found then return null; end if;
  update content_safety.report_alerts set state='sending',attempts=attempts+1,
    first_attempt_at=coalesce(first_attempt_at,now()),lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
    where report_id=item.report_id returning * into item;
  update content_safety.alert_config set attempts_today=attempts_today+1 where singleton;
  return jsonb_build_object('report_id',item.report_id,'lease_id',item.lease_id,'attempt',item.attempts);
end;
$$;

create function public.finish_content_report_alert(p_report_id uuid,p_lease_id uuid,p_result text,p_provider_id uuid default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare item content_safety.report_alerts;
begin
  if p_result not in ('ACCEPTED','RETRY','REJECTED') or p_result is null
    or (p_result='ACCEPTED' and p_provider_id is null) then
    raise exception 'INVALID_ALERT_RESULT' using errcode='22023';
  end if;
  select * into item from content_safety.report_alerts where report_id=p_report_id for update;
  if not found or item.state<>'sending' or item.lease_id is distinct from p_lease_id
    or p_lease_id is null or item.lease_until < now() then return false; end if;
  update content_safety.report_alerts set
    state=case when p_result='ACCEPTED' then 'sent'
      when p_result='RETRY' and attempts<5 and first_attempt_at>now()-interval '23 hours' then 'pending' else 'failed' end,
    provider_id=case when p_result='ACCEPTED' then p_provider_id else null end,
    accepted_at=case when p_result='ACCEPTED' then now() else null end,
    result_code=p_result,lease_id=null,lease_until=null,
    next_attempt_at=now()+make_interval(mins=>least(60,(power(2,attempts))::integer))
    where report_id=p_report_id;
  return true;
end;
$$;
revoke all on function public.claim_content_report_alert(text),
  public.finish_content_report_alert(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.claim_content_report_alert(text),
  public.finish_content_report_alert(uuid,uuid,text,uuid) to service_role;
