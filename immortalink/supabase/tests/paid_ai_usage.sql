-- Run in a transaction and ALWAYS roll back. The plan stub and usage changes
-- must never be committed. Uses one existing membership without exposing it.
begin;
create or replace function public.everroot_family_plan(p_family_id uuid)
returns text language sql stable security definer
set search_path = public, pg_temp
as $$ select case when p_family_id is null then 'free'
  else current_setting('test.plan', true) end $$;

do $$
declare
  family uuid;
  member uuid;
  plan text;
  expected integer;
  expected_ai integer;
  result jsonb;
  detail text;
begin
  select family_id, user_id into family, member
  from public.family_members where user_id is not null limit 1;
  if member is null then raise exception 'Test requires an existing membership'; end if;
  perform set_config('request.jwt.claim.sub', member::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', member, 'role', 'authenticated')::text, true);

  foreach plan in array array['everroot_family', 'everroot_legacy'] loop
    perform set_config('test.plan', plan, true);
    expected := case plan when 'everroot_family' then 7200 else 24000 end;
    expected_ai := case plan when 'everroot_family' then 500 else 1500 end;
    if (public.everroot_limits(family)->>'transcription_seconds_monthly')::integer <> expected then
      raise exception 'Wrong transcription allowance for %', plan;
    end if;
    delete from public.everroot_transcription_usage_periods
      where scope_type = 'family' and scope_id = family;
    delete from public.everroot_ai_usage_periods
      where scope_type = 'family' and scope_id = family;

    result := public.everroot_consume_transcription_usage(family, null, 300);
    if result->>'scope_type' <> 'family' or (result->>'used_seconds')::integer <> 300 then
      raise exception 'Five-minute note not fully counted against family';
    end if;
    result := public.everroot_consume_transcription_usage(family, null, expected - 300);
    if (result->>'remaining_seconds')::integer <> 0 then raise exception 'Boundary mismatch'; end if;
    begin
      perform public.everroot_consume_transcription_usage(family, null, 1);
      raise exception 'Transcription overage accepted';
    exception when sqlstate 'P0001' then
      get stacked diagnostics detail = pg_exception_detail;
      if detail is distinct from 'ERR_EVERROOT_TRANSCRIPTION_LIMIT' then raise; end if;
    end;
    result := public.everroot_consume_ai_usage(family, null, expected_ai);
    if result->>'scope_type' <> 'family' or (result->>'remaining')::integer <> 0 then
      raise exception 'AI family boundary mismatch';
    end if;
    begin
      perform public.everroot_consume_ai_usage(family, null, 1);
      raise exception 'AI overage accepted';
    exception when sqlstate 'P0001' then
      get stacked diagnostics detail = pg_exception_detail;
      if detail is distinct from 'ERR_EVERROOT_AI_LIMIT' then raise; end if;
    end;
  end loop;

  if (public.everroot_limits(null)->>'transcription_seconds_monthly')::integer <> 600 then
    raise exception 'Free allowance changed';
  end if;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  begin
    perform public.everroot_consume_ai_usage(family, null, 1);
    raise exception 'Nonmember accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.everroot_consume_transcription_usage(family, null, 1);
    raise exception 'Nonmember transcription accepted';
  exception when insufficient_privilege then null;
  end;
  if has_function_privilege('anon', 'public.everroot_limits(uuid)', 'execute') then
    raise exception 'Internal limits helper exposed';
  end if;
end $$;
rollback;
