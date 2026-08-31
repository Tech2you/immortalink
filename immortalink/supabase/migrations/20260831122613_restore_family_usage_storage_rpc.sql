-- Restore family usage reporting to the storage.objects-backed implementation.
--
-- The deployed get_family_entitlements_and_usage path was observed referencing
-- public.everroot_media_usage_entries, which is not part of the local schema.

create or replace function public.get_family_entitlements_and_usage(
  p_family_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_limits jsonb;
  v_personal_vault_id uuid;
  v_period date := public.everroot_period_start();
  v_ai_used integer := 0;
  v_transcription_used integer := 0;
  v_invites_used integer := 0;
  v_real_members integer := 0;
  v_legacy_people integer := 0;
  v_storage_bytes bigint := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_family_id is not null and not exists (
    select 1
    from public.family_members fm
    where fm.family_id = p_family_id
      and fm.user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family'
      using errcode = '42501';
  end if;

  v_limits := public.everroot_limits(p_family_id);

  if p_family_id is null then
    select v.id
      into v_personal_vault_id
      from public.vaults v
     where v.owner_id = v_user_id
     order by v.created_at asc
     limit 1;
  end if;

  select coalesce(sum(used_count), 0)
    into v_ai_used
    from public.everroot_ai_usage_periods usage
   where usage.period_start = v_period
     and (
       (
         p_family_id is not null
         and usage.scope_type = 'family'
         and usage.scope_id = p_family_id
       )
       or (
         p_family_id is null
         and usage.scope_type = 'user'
         and usage.scope_id = v_user_id
       )
     );

  select coalesce(sum(used_seconds), 0)
    into v_transcription_used
    from public.everroot_transcription_usage_periods usage
   where usage.period_start = v_period
     and (
       (
         p_family_id is not null
         and usage.scope_type = 'family'
         and usage.scope_id = p_family_id
       )
       or (
         p_family_id is null
         and usage.scope_type = 'user'
         and usage.scope_id = v_user_id
       )
     );

  if p_family_id is not null then
    select count(*)
      into v_real_members
      from public.family_members fm
     where fm.family_id = p_family_id;

    select count(*)
      into v_legacy_people
      from public.legacy_family_members lfm
     where lfm.family_id = p_family_id
       and coalesce(lfm.replaced_by_vault_id::text, '') = '';

    select coalesce(sum(used_count), 0)
      into v_invites_used
      from public.everroot_invite_usage_periods usage
     where usage.family_id = p_family_id
       and usage.period_start = v_period;
  end if;

  v_storage_bytes := public.everroot_storage_bytes_used(
    p_family_id,
    v_personal_vault_id
  );

  return jsonb_build_object(
    'plan', v_limits->>'plan',
    'limits', v_limits,
    'usage', jsonb_build_object(
      'real_members', v_real_members,
      'legacy_people', v_legacy_people,
      'memories', public.everroot_memory_count(
        p_family_id,
        v_personal_vault_id
      ),
      'photos', public.everroot_photo_count(p_family_id, v_personal_vault_id),
      'voice_notes', public.everroot_voice_note_count(
        p_family_id,
        v_personal_vault_id
      ),
      'storage_bytes', v_storage_bytes,
      'ai_responses_monthly', v_ai_used,
      'transcription_seconds_monthly', v_transcription_used,
      'invites_monthly', v_invites_used
    )
  );
end;
$$;

revoke all on function public.get_family_entitlements_and_usage(uuid)
  from public, anon, authenticated;

grant execute on function public.get_family_entitlements_and_usage(uuid)
  to authenticated;
