-- Preserve reads and deletion. No expiry-driven content deletion or retention
-- timer is introduced. Existing plan expiry and quota calculations stay intact.
create function public.everroot_family_is_read_only(p_family_id uuid)
returns boolean language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_limits jsonb;
begin
  if p_family_id is null or public.everroot_family_plan(p_family_id) <> 'free' then
    return false;
  end if;
  v_limits := public.everroot_limits(p_family_id);
  return public.everroot_storage_bytes_used(p_family_id, null) > (v_limits->>'storage_bytes')::bigint
    or public.everroot_memory_count(p_family_id, null) > (v_limits->>'memories')::integer
    or public.everroot_photo_count(p_family_id, null) > (v_limits->>'photos')::integer
    or public.everroot_voice_note_count(p_family_id, null) > (v_limits->>'voice_notes')::integer
    or (select count(*) from public.family_members where family_id = p_family_id) > (v_limits->>'real_members')::integer
    or (select count(*) from public.legacy_family_members
      where family_id = p_family_id and replaced_by_vault_id is null) > (v_limits->>'legacy_people')::integer;
end;
$$;

create function public.everroot_assert_family_writable(p_family_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if public.everroot_family_is_read_only(p_family_id) then
    perform public.everroot_quota_error('ERR_EVERROOT_READ_ONLY',
      'Your family is over the free plan limits. Existing memories are still available. Renew your plan or reduce usage to add more.');
  end if;
end;
$$;

-- Attach to existing quota enforcement points, retaining their authorization,
-- locking and usage metering. Fail rather than silently ignore schema drift.
do $$
declare
  v_signature regprocedure;
  v_definition text;
  v_marker text;
  v_family_expression text;
begin
  foreach v_signature in array array[
    'public.everroot_assert_memory_capacity()'::regprocedure,
    'public.everroot_assert_legacy_memory_capacity()'::regprocedure,
    'public.everroot_assert_legacy_person_capacity()'::regprocedure,
    'public.everroot_assert_photo_capacity()'::regprocedure,
    'public.everroot_assert_voice_note_capacity()'::regprocedure,
    'public.everroot_assert_storage_object_capacity()'::regprocedure,
    'public.everroot_consume_ai_usage(uuid,uuid,integer)'::regprocedure,
    'public.everroot_consume_transcription_usage(uuid,uuid,integer)'::regprocedure
  ] loop
    v_definition := pg_get_functiondef(v_signature);
    v_family_expression := case
      when v_signature::text like '%assert_legacy_%' then 'new.family_id'
      else 'v_family_id' end;
    -- Every implementation has resolved and authorized its family before the
    -- first limit lookup. AI functions instead resolve the plan first.
    if v_signature::text like '%consume_%' then
      v_marker := 'v_plan := public.everroot_family_plan(v_family_id);';
    else
      v_marker := 'v_limit := public.everroot_limit_';
    end if;
    if position(v_marker in v_definition) = 0 then
      raise exception 'Review read-only guard insertion for %', v_signature;
    end if;
    v_definition := replace(v_definition, v_marker,
      'perform public.everroot_assert_family_writable(' || v_family_expression || ');' || chr(10) || '  ' || v_marker);
    execute v_definition;
  end loop;
end;
$$;

revoke all on function public.everroot_family_is_read_only(uuid) from public, anon, authenticated;
revoke all on function public.everroot_assert_family_writable(uuid) from public, anon, authenticated;
grant execute on function public.everroot_family_is_read_only(uuid) to service_role;
grant execute on function public.everroot_assert_family_writable(uuid) to service_role;
