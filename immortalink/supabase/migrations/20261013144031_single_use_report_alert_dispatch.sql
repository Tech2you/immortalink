-- pg_net queue ACLs are platform-owned and cannot be revoked per project.
-- Only a one-use, 90-second authorization for one fixed alert enters that queue.
-- No reusable worker token, Resend key or Supabase service key is queued.
create table content_safety.alert_invocations (
  token_hash text primary key check (token_hash ~ '^[a-f0-9]{64}$'),
  report_id uuid not null references content_safety.report_alerts(report_id) on delete cascade,
  expires_at timestamptz not null default now()+interval '90 seconds',
  consumed_at timestamptz
);
create index alert_invocations_report_idx on content_safety.alert_invocations(report_id,expires_at);
alter table content_safety.alert_invocations enable row level security;
revoke all on content_safety.alert_invocations from public,anon,authenticated;
grant all on content_safety.alert_invocations to service_role;

create or replace function public.claim_content_report_alert(p_worker_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg content_safety.alert_config; item content_safety.report_alerts; invocation content_safety.alert_invocations;
begin
  select * into cfg from content_safety.alert_config where singleton for update;
  if p_worker_token is null or length(p_worker_token)<>64 then
    raise exception 'ALERT_WORKER_UNAUTHORIZED' using errcode='42501';
  end if;
  select * into invocation from content_safety.alert_invocations
    where token_hash=encode(sha256(convert_to(p_worker_token,'UTF8')),'hex')
      and expires_at>now() and consumed_at is null for update;
  if not found then raise exception 'ALERT_WORKER_UNAUTHORIZED' using errcode='42501'; end if;
  update content_safety.alert_invocations set consumed_at=now() where token_hash=invocation.token_hash;
  if not cfg.enabled then return null; end if;
  if cfg.budget_day <> (now() at time zone 'UTC')::date then
    update content_safety.alert_config set budget_day=(now() at time zone 'UTC')::date,attempts_today=0 where singleton;
    cfg.attempts_today:=0;
  end if;
  update content_safety.report_alerts set state='failed',result_code='REVIEW_REQUIRED',lease_id=null,lease_until=null
    where state in ('pending','sending') and (lease_until is null or lease_until < now())
      and (attempts>=5 or first_attempt_at < now()-interval '23 hours');
  update content_safety.report_alerts a set state='skipped',result_code='REPORT_CLOSED'
    where a.state='pending' and a.attempts=0 and exists(select 1 from public.content_reports r
      where r.id=a.report_id and r.status not in ('open','reviewing'));
  if cfg.attempts_today >= cfg.daily_attempt_limit then return null; end if;
  select * into item from content_safety.report_alerts where report_id=invocation.report_id
    and ((state='pending' and next_attempt_at<=now()) or (state='sending' and lease_until<now())) for update;
  if not found then return null; end if;
  update content_safety.report_alerts set state='sending',attempts=attempts+1,
    first_attempt_at=coalesce(first_attempt_at,now()),lease_id=gen_random_uuid(),lease_until=now()+interval '2 minutes'
    where report_id=item.report_id returning * into item;
  update content_safety.alert_config set attempts_today=attempts_today+1 where singleton;
  return jsonb_build_object('report_id',item.report_id,'lease_id',item.lease_id,'attempt',item.attempts);
end;
$$;

create or replace function content_safety.dispatch_report_alert()
returns bigint language plpgsql security definer set search_path='' as $$
declare token text; target uuid; request_id bigint;
begin
  -- Serialize dispatch creation, not the external HTTP request.
  perform 1 from content_safety.alert_config where singleton for update;
  if not exists(select 1 from content_safety.alert_config where singleton and enabled
    and (attempts_today<daily_attempt_limit or budget_day<(now() at time zone 'UTC')::date)) then return null; end if;
  delete from content_safety.alert_invocations where expires_at<now()-interval '1 day';
  select a.report_id into target from content_safety.report_alerts a where
    ((a.state='pending' and a.next_attempt_at<=now()) or (a.state='sending' and a.lease_until<now()))
    and not exists(select 1 from content_safety.alert_invocations i
      where i.report_id=a.report_id and i.expires_at>now() and i.consumed_at is null)
    order by a.created_at limit 1 for update;
  if target is null then return null; end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into content_safety.alert_invocations(token_hash,report_id)
    values(encode(sha256(convert_to(token,'UTF8')),'hex'),target);
  select net.http_post(
    url:='https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/send_content_report_alert',
    headers:=jsonb_build_object('Content-Type','application/json','x-report-alert-token',token),
    body:='{}'::jsonb,timeout_milliseconds:=40000
  ) into request_id;
  return request_id;
end;
$$;
alter table content_safety.alert_config drop column worker_token_hash;
-- Retire the generated legacy credential. Its old queue value can no longer
-- authorize anything because no matching one-use invocation exists.
delete from vault.secrets where name='content_report_alert_worker_token';
revoke all on function public.claim_content_report_alert(text) from public,anon,authenticated;
grant execute on function public.claim_content_report_alert(text) to service_role;
