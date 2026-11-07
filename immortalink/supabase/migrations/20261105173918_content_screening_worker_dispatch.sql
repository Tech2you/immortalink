-- Install disabled. A separate activation enables the worker after the current
-- app, publication gates and hosted checks have been verified together.
create table content_safety.screening_worker_config (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  day date,
  runs integer not null default 0 check(runs>=0),
  max_daily_runs integer not null default 1000 check(max_daily_runs between 1 and 1000)
);
insert into content_safety.screening_worker_config(singleton) values(true);
create table content_safety.screening_runs (
  token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  busy_until timestamptz not null,
  claimed boolean not null default false
);
alter table content_safety.screening_worker_config enable row level security;
alter table content_safety.screening_runs enable row level security;
revoke all on content_safety.screening_worker_config,content_safety.screening_runs
  from public,anon,authenticated,service_role;

create function public.dispatch_content_screening()
returns bigint language plpgsql security definer set search_path='' as $$
declare c content_safety.screening_worker_config; token text; request_id bigint;
  stamp timestamptz:=clock_timestamp(); today date:=(clock_timestamp() at time zone 'UTC')::date;
begin
  select * into c from content_safety.screening_worker_config where singleton for update;
  if c.enabled is not true or not exists(select 1 from content_safety.screening_controls where enabled and enforce_publication) then return null; end if;
  if c.day is distinct from today then
    update content_safety.screening_worker_config set day=today,runs=0 where singleton;
    c.runs:=0;
  end if;
  if c.runs>=c.max_daily_runs then return null; end if;
  delete from content_safety.screening_runs where (claimed and busy_until<=stamp) or (not claimed and expires_at<=stamp);
  if exists(select 1 from content_safety.screening_runs) then return null; end if;
  if not exists(select 1 from content_safety.screening_jobs where
    (state='queued' and available_at<=stamp) or (state='leased' and lease_until<=stamp)) then return null; end if;
  token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
  insert into content_safety.screening_runs values(encode(sha256(convert_to(token,'UTF8')),'hex'),stamp+interval '90 seconds',stamp+interval '6 minutes',false);
  update content_safety.screening_worker_config set runs=runs+1 where singleton;
  select net.http_post(
    url:='https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/process_content_screening',
    headers:=jsonb_build_object('Content-Type','application/json','x-screening-run-token',token),
    body:='{}'::jsonb,timeout_milliseconds:=10000
  ) into request_id;
  return request_id;
end;
$$;

create function public.claim_screening_run(p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
declare claimed_hash text;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then return false; end if;
  perform 1 from content_safety.screening_worker_config where singleton and enabled for update;
  if not found then return false; end if;
  update content_safety.screening_runs set claimed=true,busy_until=clock_timestamp()+interval '6 minutes'
    where token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') and not claimed and expires_at>clock_timestamp()
    returning token_hash into claimed_hash;
  return claimed_hash is not null;
end;
$$;

create function public.finish_screening_run(p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
declare removed_hash text;
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then return false; end if;
  perform 1 from content_safety.screening_worker_config where singleton for update;
  delete from content_safety.screening_runs where claimed and token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
    returning token_hash into removed_hash;
  if removed_hash is null then return false; end if;
  perform public.dispatch_content_screening();
  return true;
end;
$$;

create function content_safety.wake_screening_worker()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Failure to wake is recoverable by the cron safety sweep. It must not undo a
  -- user's successful save. The screening queue remains authoritative.
  if new.state='queued' and new.available_at<=clock_timestamp() then
    begin perform public.dispatch_content_screening(); exception when others then null; end;
  end if;
  return null;
end;
$$;
create trigger wake_screening_worker after insert or update on content_safety.screening_jobs
  for each row execute function content_safety.wake_screening_worker();
revoke all on function content_safety.wake_screening_worker() from public,anon,authenticated,service_role;
revoke all on function public.dispatch_content_screening(),public.claim_screening_run(text),public.finish_screening_run(text)
  from public,anon,authenticated,service_role;
grant execute on function public.dispatch_content_screening(),public.claim_screening_run(text),public.finish_screening_run(text) to service_role;
-- No cron is created here. Activation installs a one-minute recovery sweep.
