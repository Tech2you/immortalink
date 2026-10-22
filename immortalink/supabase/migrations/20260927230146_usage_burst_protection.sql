-- Short per-person burst protection; monthly plan allowances stay unchanged.
create table public.everroot_usage_bursts (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('ai','transcription')),
  window_started_at timestamptz not null,
  units integer not null check(units>=0),
  primary key(user_id,kind)
);
alter table public.everroot_usage_bursts enable row level security;
revoke all on public.everroot_usage_bursts from public,anon,authenticated;
grant all on public.everroot_usage_bursts to service_role;

create function public.everroot_assert_usage_burst(p_kind text,p_units integer default 1)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_limit integer := case p_kind when 'ai' then 6 when 'transcription' then 3 end;
  v_burst public.everroot_usage_bursts%rowtype;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  if v_limit is null or p_units is null or p_units<1 then raise exception 'Invalid usage request'; end if;
  perform pg_advisory_xact_lock(hashtext('usage-burst:'||v_user::text||':'||p_kind));
  select * into v_burst from public.everroot_usage_bursts where user_id=v_user and kind=p_kind;
  if not found or v_burst.window_started_at <= now()-interval '1 minute' then
    v_burst.units := 0; v_burst.window_started_at := now();
  end if;
  if p_units > v_limit-v_burst.units then
    raise exception 'Please wait a minute before requesting more AI or transcription.'
      using errcode='P0001',detail='ERR_EVERROOT_USAGE_BURST';
  end if;
  insert into public.everroot_usage_bursts(user_id,kind,window_started_at,units)
  values(v_user,p_kind,v_burst.window_started_at,v_burst.units+p_units)
  on conflict(user_id,kind) do update set window_started_at=excluded.window_started_at,units=excluded.units;
end;
$$;
revoke all on function public.everroot_assert_usage_burst(text,integer) from public,anon,authenticated;
grant execute on function public.everroot_assert_usage_burst(text,integer) to service_role;

do $$
declare v_name text; v_definition text; v_guard text;
begin
  foreach v_name in array array['everroot_consume_ai_usage','everroot_consume_transcription_usage'] loop
    v_definition := pg_get_functiondef(to_regprocedure('public.'||v_name||'(uuid,uuid,integer)'));
    if v_definition is null or position('v_plan := public.everroot_family_plan(v_family_id);' in v_definition)=0 then
      raise exception 'Unexpected usage function definition: %',v_name;
    end if;
    v_guard := case when v_name='everroot_consume_ai_usage'
      then 'perform public.everroot_assert_usage_burst(''ai'',p_units);'
      else 'perform public.everroot_assert_usage_burst(''transcription'',1);' end;
    execute replace(v_definition,'v_plan := public.everroot_family_plan(v_family_id);',
      v_guard||E'\n  v_plan := public.everroot_family_plan(v_family_id);');
  end loop;
end;
$$;
