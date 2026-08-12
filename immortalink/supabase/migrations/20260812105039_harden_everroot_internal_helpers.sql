-- Keep EverRoot quota helpers off the public RPC surface.
--
-- The app/Edge Functions intentionally call only:
-- - public.everroot_consume_ai_usage(uuid, uuid, integer)
-- - public.get_family_entitlements_and_usage(uuid)
--
-- The remaining helpers are used by triggers or by other SECURITY DEFINER
-- functions and should not be directly callable by every signed-in user.

revoke all on function public.everroot_touch_updated_at()
  from public, anon, authenticated;
revoke all on function public.everroot_family_plan(uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_limits(uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_limit_int(uuid, text)
  from public, anon, authenticated;
revoke all on function public.everroot_limit_bigint(uuid, text)
  from public, anon, authenticated;
revoke all on function public.everroot_quota_error(text, text)
  from public, anon, authenticated;
revoke all on function public.everroot_family_for_vault(uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_assert_can_add_family_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_assert_family_member_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_invite_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_legacy_person_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_memory_count(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_assert_memory_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_legacy_memory_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_photo_count(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_voice_note_count(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_family_id_from_legacy_member(uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_legacy_media_count(text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_media_bucket_ids()
  from public, anon, authenticated;
revoke all on function public.everroot_storage_metadata_size(jsonb)
  from public, anon, authenticated;
revoke all on function public.everroot_try_uuid(text)
  from public, anon, authenticated;
revoke all on function public.everroot_storage_bytes_used(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.everroot_assert_storage_object_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_storage_capacity(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.everroot_assert_photo_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_voice_note_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_vault_avatar_storage_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_assert_legacy_avatar_storage_capacity()
  from public, anon, authenticated;
revoke all on function public.everroot_period_start(timestamptz)
  from public, anon, authenticated;

grant execute on function public.everroot_touch_updated_at()
  to service_role;
grant execute on function public.everroot_family_plan(uuid)
  to service_role;
grant execute on function public.everroot_limits(uuid)
  to service_role;
grant execute on function public.everroot_limit_int(uuid, text)
  to service_role;
grant execute on function public.everroot_limit_bigint(uuid, text)
  to service_role;
grant execute on function public.everroot_quota_error(text, text)
  to service_role;
grant execute on function public.everroot_family_for_vault(uuid)
  to service_role;
grant execute on function public.everroot_assert_can_add_family_member(uuid, uuid)
  to service_role;
grant execute on function public.everroot_assert_family_member_capacity()
  to service_role;
grant execute on function public.everroot_assert_invite_capacity()
  to service_role;
grant execute on function public.everroot_assert_legacy_person_capacity()
  to service_role;
grant execute on function public.everroot_memory_count(uuid, uuid)
  to service_role;
grant execute on function public.everroot_assert_memory_capacity()
  to service_role;
grant execute on function public.everroot_assert_legacy_memory_capacity()
  to service_role;
grant execute on function public.everroot_photo_count(uuid, uuid)
  to service_role;
grant execute on function public.everroot_voice_note_count(uuid, uuid)
  to service_role;
grant execute on function public.everroot_family_id_from_legacy_member(uuid)
  to service_role;
grant execute on function public.everroot_legacy_media_count(text, uuid, uuid)
  to service_role;
grant execute on function public.everroot_media_bucket_ids()
  to service_role;
grant execute on function public.everroot_storage_metadata_size(jsonb)
  to service_role;
grant execute on function public.everroot_try_uuid(text)
  to service_role;
grant execute on function public.everroot_storage_bytes_used(uuid, uuid)
  to service_role;
grant execute on function public.everroot_assert_storage_object_capacity()
  to service_role;
grant execute on function public.everroot_assert_storage_capacity(uuid, uuid, text)
  to service_role;
grant execute on function public.everroot_assert_photo_capacity()
  to service_role;
grant execute on function public.everroot_assert_voice_note_capacity()
  to service_role;
grant execute on function public.everroot_assert_vault_avatar_storage_capacity()
  to service_role;
grant execute on function public.everroot_assert_legacy_avatar_storage_capacity()
  to service_role;
grant execute on function public.everroot_period_start(timestamptz)
  to service_role;

-- Keep the two intentional public client RPCs available to signed-in users.
revoke all on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  from public, anon;
grant execute on function public.everroot_consume_ai_usage(uuid, uuid, integer)
  to authenticated, service_role;

revoke all on function public.get_family_entitlements_and_usage(uuid)
  from public, anon;
grant execute on function public.get_family_entitlements_and_usage(uuid)
  to authenticated, service_role;
