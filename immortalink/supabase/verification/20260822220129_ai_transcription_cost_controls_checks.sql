-- EverRoot AI/transcription cost-control verification checks.
--
-- Safe read-only checks for production after applying
-- 20260822220129_everroot_ai_transcription_cost_controls.sql.
-- Boundary inserts should only be run in staging or inside an explicit
-- transaction that is rolled back.

-- 1) Limits expose separate AI and transcription allowances.
select
  'free' as plan,
  public.everroot_limits(null)->>'ai_responses_monthly' as ai_responses_monthly,
  public.everroot_limits(null)->>'transcription_seconds_monthly' as transcription_seconds_monthly;

-- Replace with a paid family id before running in staging/production.
-- select
--   'family' as plan,
--   public.everroot_limits('00000000-0000-0000-0000-000000000000'::uuid)->>'ai_responses_monthly' as ai_responses_monthly,
--   public.everroot_limits('00000000-0000-0000-0000-000000000000'::uuid)->>'transcription_seconds_monthly' as transcription_seconds_monthly;

-- 2) Durable transcription usage table exists.
select to_regclass('public.everroot_transcription_usage_periods') as transcription_usage_table;

-- 2b) Voice-note duration columns exist for duration-aware transcription
-- accounting on newly recorded notes. Existing rows may remain null.
select
  table_name,
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('memory_voice_notes', 'legacy_memory_voice_notes')
  and column_name = 'duration_seconds'
order by table_name;

-- 3) SECURITY DEFINER EverRoot functions should not be executable by public
-- or anon. Expected result: 0 rows.
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
    or p.proname = 'get_family_entitlements_and_usage'
  )
order by p.proname, args, grantee;

-- 4) Authenticated RPC surface should include the public app entrypoints.
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
  and p.proname in (
    'everroot_consume_ai_usage',
    'everroot_consume_transcription_usage',
    'get_family_entitlements_and_usage'
  )
order by p.proname, args;

-- 5) Staging-only boundary tests:
-- Free:
--   * everroot_consume_transcription_usage(..., 60) succeeds 10 times.
--   * the 11th 60-second call rejects with ERR_EVERROOT_TRANSCRIPTION_LIMIT.
--   * calls above 120 seconds are capped to the current per-note ceiling.
--   * everroot_consume_ai_usage still has its separate 20-response allowance.
-- Paid/TestFlight-entitled family:
--   * transcription usage is scoped to family, not the individual user.
--   * 300 calls at 120 seconds are allowed for 36,000 monthly seconds.
--   * the 301st 120-second call rejects with ERR_EVERROOT_TRANSCRIPTION_LIMIT.
-- Security:
--   * non-family members cannot consume a paid family's transcription quota.
--   * authenticated users can select only their own/family usage rows via RLS.
