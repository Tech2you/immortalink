-- Harden public RPC/table exposure discovered by Supabase advisors.
--
-- This migration is intentionally grant/config only:
-- - it does not change table data;
-- - it does not alter family tree, invite, media, or entitlement logic;
-- - app-facing family leave RPCs remain available to signed-in users.

-- Entitlement and usage tables are read by signed-in family members through RLS.
-- Keep writes server-side for the future Apple subscription validator.
revoke all on table public.family_entitlements
  from anon;
revoke all on table public.everroot_ai_usage_periods
  from anon;
revoke all on table public.everroot_invite_usage_periods
  from anon;

revoke insert, update, delete, truncate, references, trigger
  on table public.family_entitlements
  from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.everroot_ai_usage_periods
  from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.everroot_invite_usage_periods
  from authenticated;

grant select on table public.family_entitlements
  to authenticated;
grant select on table public.everroot_ai_usage_periods
  to authenticated;
grant select on table public.everroot_invite_usage_periods
  to authenticated;

-- Internal cleanup/count helpers should not be callable from the public API.
revoke all on function public.count_family_rows_if_present(text, uuid)
  from public, anon, authenticated;
grant execute on function public.count_family_rows_if_present(text, uuid)
  to service_role;

revoke all on function public.family_tree_remaining_summary(uuid)
  from public, anon, authenticated;
grant execute on function public.family_tree_remaining_summary(uuid)
  to service_role;

revoke all on function public.cleanup_empty_family_group(uuid)
  from public, anon, authenticated;
grant execute on function public.cleanup_empty_family_group(uuid)
  to service_role;

revoke all on function public.destroy_empty_family_group_tree(uuid)
  from public, anon, authenticated;
grant execute on function public.destroy_empty_family_group_tree(uuid)
  to service_role;

revoke all on function public.cleanup_empty_family_group_after_membership_change()
  from public, anon, authenticated;
revoke all on function public.lock_family_membership_family()
  from public, anon, authenticated;

-- App-facing leave-family RPCs require signed-in users and validate auth.uid().
revoke all on function public.get_family_leave_impact(uuid)
  from public, anon;
grant execute on function public.get_family_leave_impact(uuid)
  to authenticated;

revoke all on function public.leave_family(uuid)
  from public, anon;
grant execute on function public.leave_family(uuid)
  to authenticated;

revoke all on function public.leave_family_confirmed(uuid)
  from public, anon;
grant execute on function public.leave_family_confirmed(uuid)
  to authenticated;

-- Clear mutable-search-path advisor findings without changing function bodies.
alter function public.can_access_vault(uuid)
  set search_path = public, pg_temp;
alter function public.is_user_in_vault_family(uuid)
  set search_path = public, pg_temp;
alter function public.match_legacy_memory_chunks(uuid, vector, integer)
  set search_path = public, pg_temp;
alter function public.match_memory_chunks(uuid, vector, integer)
  set search_path = public, pg_temp;
alter function public.set_updated_at()
  set search_path = public, pg_temp;
alter function public.set_vault_owner_id()
  set search_path = public, pg_temp;
