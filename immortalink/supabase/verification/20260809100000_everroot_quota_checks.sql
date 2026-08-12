-- EverRoot entitlement/quota verification checks.
--
-- Run after applying 20260809100000_everroot_entitlements_and_quotas.sql to a
-- staging Supabase project. Do not run destructive boundary tests in production.

-- 1) Product limits should match the launch model.
select
  'free' as plan,
  public.everroot_limits(null)->>'real_members' as real_members,
  public.everroot_limits(null)->>'legacy_people' as legacy_people,
  public.everroot_limits(null)->>'memories' as memories,
  public.everroot_limits(null)->>'photos' as photos,
  public.everroot_limits(null)->>'voice_notes' as voice_notes,
  public.everroot_limits(null)->>'storage_bytes' as storage_bytes,
  public.everroot_limits(null)->>'ai_responses_monthly' as ai_responses_monthly,
  public.everroot_limits(null)->>'invites_monthly' as invites_monthly;

-- 2) Durable usage/accounting tables and quota triggers should exist.
select to_regclass('public.family_entitlements') as family_entitlements_table;
select to_regclass('public.everroot_ai_usage_periods') as ai_usage_table;
select to_regclass('public.everroot_invite_usage_periods') as invite_usage_table;

select
  n.nspname as schema,
  c.relname as table_name,
  t.tgname as trigger_name,
  p.proname as function_name,
  not t.tgisinternal as user_trigger
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
where n.nspname in ('public', 'storage')
  and t.tgname like 'everroot_%'
order by c.relname, t.tgname;

-- 3) SECURITY DEFINER functions in this migration should not be executable by
-- public or anon. Expected result: 0 rows.
select
  n.nspname as schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  r.rolname as grantee
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a on true
join pg_roles r on r.oid = a.grantee
where n.nspname = 'public'
  and p.prosecdef = true
  and a.privilege_type = 'EXECUTE'
  and r.rolname in ('public', 'anon')
  and (
    p.proname like 'everroot_%'
    or p.proname in ('get_family_entitlements_and_usage')
  )
order by p.proname, args, grantee;

-- 4) Public RPC surface. Expected callable functions for authenticated users:
-- everroot_consume_ai_usage, get_family_entitlements_and_usage, and the existing
-- join-family RPCs. Helper functions should not need direct app execution.
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  r.rolname as grantee
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a on true
join pg_roles r on r.oid = a.grantee
where n.nspname = 'public'
  and a.privilege_type = 'EXECUTE'
  and r.rolname = 'authenticated'
  and (
    p.proname like 'everroot_%'
    or p.proname in (
      'get_family_entitlements_and_usage',
      'join_family_by_invite',
      'join_family_by_relationship_invite'
    )
  )
order by p.proname, args;

-- 5) Inspect deployed family entitlements and usage. Replace the UUID with a
-- staging family id before running.
-- select public.get_family_entitlements_and_usage('00000000-0000-0000-0000-000000000000'::uuid);

-- 6) Boundary tests to perform only in a disposable staging project:
-- - Free family:
--   * 1st real member allowed, 2nd rejected with ERR_EVERROOT_MEMBER_LIMIT.
--   * same user creating/joining another Free family rejected with
--     ERR_EVERROOT_FREE_FAMILY_LIMIT.
--   * 8th Legacy Person allowed, 9th rejected.
--   * 100th memory allowed, 101st rejected.
--   * 100th photo allowed, 101st rejected.
--   * 25th voice note allowed, 26th rejected.
--   * 20th monthly AI use allowed, 21st rejected.
--   * invite creation rejected with ERR_EVERROOT_FAMILY_REQUIRED.
-- - EverRoot Family:
--   * 8th real member allowed, 9th rejected.
--   * 100th Legacy Person allowed, 101st rejected.
--   * 1000th memory allowed, 1001st rejected.
--   * 2000th photo allowed, 2001st rejected.
--   * 500th voice note allowed, 501st rejected.
--   * 50th monthly invite allowed, 51st rejected; deleting redeemed invites
--     must not reduce everroot_invite_usage_periods.used_count.
--   * 500th monthly AI use allowed, 501st rejected.
-- - Downgrade:
--   * Existing over-limit content remains selectable.
--   * New inserts are rejected until usage falls below the Free limit or the
--     entitlement returns to active EverRoot Family.
-- - Storage:
--   * Existing files remain accessible.
--   * New storage.objects writes reject once metadata sizes exceed
--     storage_bytes for the applicable plan.
--   * Direct uploads into protected media buckets with invalid EverRoot paths
--     reject with ERR_EVERROOT_STORAGE_PATH.
