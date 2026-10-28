-- Local-only screening extension. No app hooks, scheduling, publication grants,
-- existing Storage policies, or billing functions are changed.
alter table content_safety.screening_jobs add column processing_lease_token uuid;

create table content_safety.screening_processing_limits (
  scope text primary key check (scope in ('global_day','global_month','user_hour')),
  max_bytes bigint not null check (max_bytes between 1 and 107374182400),
  max_jobs integer not null check (max_jobs between 1 and 100000),
  max_images integer not null check (max_images between 1 and 400000),
  max_output_bytes bigint not null check (max_output_bytes between 1 and 107374182400)
);
insert into content_safety.screening_processing_limits values
  ('global_day',268435456,1000,1000,268435456),
  ('global_month',2147483648,10000,5000,2147483648),
  ('user_hour',50331648,20,40,50331648);

create table content_safety.screening_processing_budgets (
  scope text not null references content_safety.screening_processing_limits(scope),
  subject text not null,
  window_start timestamptz not null,
  used_bytes bigint not null check (used_bytes>=0),
  used_jobs integer not null check (used_jobs>=0),
  used_images integer not null check (used_images>=0),
  used_output_bytes bigint not null check (used_output_bytes>=0),
  primary key(scope,subject)
);
alter table content_safety.screening_processing_limits enable row level security;
alter table content_safety.screening_processing_budgets enable row level security;
revoke all on content_safety.screening_processing_limits,
  content_safety.screening_processing_budgets from public,anon,authenticated,service_role;

-- The first prepare reserves the whole attempt BEFORE returning bytes to fetch.
-- Rechecks on this lease reuse its reservation. New leases, edits and failed
-- attempts do not refund capacity. Counters are durable, not worker-local.
create or replace function public.prepare_content_screening(p_job uuid,p_lease uuid,p_authorize boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  c content_safety.screening_controls; j content_safety.screening_jobs; s jsonb;
  stamp timestamptz;
  day_window bigint; hour_window bigint;
  global_used integer; user_used integer;
  source_bytes bigint; image_count integer; output_bytes bigint;
  lim content_safety.screening_processing_limits;
  b content_safety.screening_processing_budgets;
  subject_key text; period_start timestamptz; budget_blocked boolean:=false;
  reset_at timestamptz; next_reset timestamptz;
begin
  perform content_safety.media_lifecycle_lock();
  select * into c from content_safety.screening_controls where singleton for update;
  select * into j from content_safety.screening_jobs where id=p_job for update;
  if not found or j.state<>'leased' or j.lease_token is distinct from p_lease
    or j.lease_until<=clock_timestamp() or j.dispatched or p_authorize is null then
    return jsonb_build_object('code','LEASE_UNAVAILABLE');
  end if;
  s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
  if s->>'code'<>'READY' or s->>'revision' is distinct from j.revision then
    update content_safety.screening_jobs set state='stale',code='SOURCE_CHANGED',
      lease_token=null,lease_until=null,updated_at=clock_timestamp() where id=j.id;
    return jsonb_build_object('code','SOURCE_CHANGED');
  end if;
  stamp:=clock_timestamp();
  day_window:=floor(extract(epoch from stamp)/86400)::bigint;
  hour_window:=floor(extract(epoch from stamp)/3600)::bigint;
  select used into global_used from content_safety.screening_budgets
    where scope='global_day' and subject='all' and window_start=day_window;
  select used into user_used from content_safety.screening_budgets
    where scope='user_hour' and subject=j.actor_id::text and window_start=hour_window;

  -- Do not repeatedly decode photos while the downstream allowance is exhausted.
  -- Dispatch still reserves its own allowance atomically immediately before send.
  if coalesce(global_used,0)>=c.max_daily_requests or coalesce(user_used,0)>=c.max_user_hourly_requests then
    update content_safety.screening_jobs set state='queued',code='BUDGET_LIMIT',attempts=attempts-1,
      lease_token=null,lease_until=null,available_at=stamp+interval '1 hour',
      updated_at=stamp where id=j.id;
    return jsonb_build_object('code','BUDGET_LIMIT');
  end if;

  if j.processing_lease_token is distinct from j.lease_token then
    image_count:=jsonb_array_length(s->'images');
    select coalesce(sum((img->'metadata'->>'size')::bigint),0) into source_bytes
      from jsonb_array_elements(s->'images') img;
    -- Reserve one binary worker response AND provider base64 for each bounded
    -- 2 MiB JPEG, plus text escaping/wrappers. No refunds on failed attempts.
    output_bytes:=image_count::bigint*(2097152+2796204)+6::bigint*octet_length(s->>'text')+1024;
    if source_bytes>25165824 then
      update content_safety.screening_jobs set state='review',code='SOURCE_BATCH_TOO_LARGE',
        lease_token=null,lease_until=null,updated_at=stamp where id=j.id;
      return jsonb_build_object('code','SOURCE_BATCH_TOO_LARGE');
    end if;
    -- Missing limits are a configuration error, never unlimited capacity.
    if (select count(*) from content_safety.screening_processing_limits)<>3 then
      return jsonb_build_object('code','PROCESSING_LIMITS_UNAVAILABLE');
    end if;
    for lim in select * from content_safety.screening_processing_limits order by scope for share loop
      subject_key:=case when lim.scope='user_hour' then j.actor_id::text else 'all' end;
      period_start:=date_trunc(case lim.scope when 'global_month' then 'month'
        when 'global_day' then 'day' else 'hour' end,stamp at time zone 'UTC') at time zone 'UTC';
      next_reset:=case lim.scope when 'global_month' then
        ((period_start at time zone 'UTC')+interval '1 month') at time zone 'UTC'
        when 'global_day' then period_start+interval '24 hours' else period_start+interval '1 hour' end;
      select * into b from content_safety.screening_processing_budgets
        where scope=lim.scope and subject=subject_key and window_start=period_start;
      if source_bytes>lim.max_bytes-coalesce(b.used_bytes,0)
        or coalesce(b.used_jobs,0)>=lim.max_jobs
        or image_count>lim.max_images-coalesce(b.used_images,0)
        or output_bytes>lim.max_output_bytes-coalesce(b.used_output_bytes,0) then
        budget_blocked:=true; reset_at:=greatest(reset_at,next_reset);
      end if;
    end loop;
    if budget_blocked then
      update content_safety.screening_jobs set state='queued',code='PROCESSING_BUDGET_LIMIT',
        attempts=attempts-1,lease_token=null,lease_until=null,available_at=reset_at,updated_at=stamp where id=j.id;
      return jsonb_build_object('code','PROCESSING_BUDGET_LIMIT');
    end if;
    for lim in select * from content_safety.screening_processing_limits order by scope loop
      subject_key:=case when lim.scope='user_hour' then j.actor_id::text else 'all' end;
      period_start:=date_trunc(case lim.scope when 'global_month' then 'month'
        when 'global_day' then 'day' else 'hour' end,stamp at time zone 'UTC') at time zone 'UTC';
      insert into content_safety.screening_processing_budgets values
        (lim.scope,subject_key,period_start,source_bytes,1,image_count,output_bytes)
        on conflict(scope,subject) do update set window_start=excluded.window_start,
          used_bytes=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_bytes+excluded.used_bytes else excluded.used_bytes end,
          used_jobs=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_jobs+1 else 1 end,
          used_images=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_images+excluded.used_images else excluded.used_images end,
          used_output_bytes=case when screening_processing_budgets.window_start=excluded.window_start
            then screening_processing_budgets.used_output_bytes+excluded.used_output_bytes else excluded.used_output_bytes end;
    end loop;
    update content_safety.screening_jobs set processing_lease_token=lease_token,updated_at=stamp where id=j.id;
  end if;
  if not p_authorize then return s || jsonb_build_object('processing_reserved',true); end if;
  insert into content_safety.screening_budgets values('global_day','all',day_window,1)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+1 else 1 end;
  insert into content_safety.screening_budgets values('user_hour',j.actor_id::text,hour_window,1)
    on conflict(scope,subject) do update set window_start=excluded.window_start,
      used=case when screening_budgets.window_start=excluded.window_start then screening_budgets.used+1 else 1 end;
  update content_safety.screening_jobs set dispatched=true,code='DISPATCH_RESERVED',
    updated_at=stamp where id=j.id;
  return jsonb_build_object('code','DISPATCH_RESERVED','revision',j.revision);
end;
$$;
revoke all on function public.prepare_content_screening(uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.prepare_content_screening(uuid,uuid,boolean) to service_role;
