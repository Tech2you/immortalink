-- Empty-family cleanup verification checklist.
--
-- Run these against a staging/scratch Supabase project after applying
-- 20260808120000_cleanup_empty_family_groups.sql. Do not run destructive cases
-- against production data.
--
-- Replace the UUID placeholders with known staging test users/families.

-- 1. Family with multiple real users:
-- Expected: get_family_leave_impact(...)->>'is_last_real_member' is false.
select public.get_family_leave_impact('00000000-0000-0000-0000-000000000001');

-- 2. Last real user leaves, no legacy/tree data:
-- Expected: leave_family(...) succeeds, clears stale vault family_id if needed,
-- and silently removes only the empty family_groups row.
select public.get_family_leave_impact('00000000-0000-0000-0000-000000000002');
select public.leave_family('00000000-0000-0000-0000-000000000002');

-- 3. Last real user leaves, legacy people remain:
-- Expected: get_family_leave_impact requires confirmation and leave_family(...)
-- raises ERR_LEAVE_FAMILY_REQUIRES_CONFIRMATION.
select public.get_family_leave_impact('00000000-0000-0000-0000-000000000003');
select public.leave_family('00000000-0000-0000-0000-000000000003');

-- 4. Last real user leaves, relationship rows remain:
-- Expected: same as case 3; no relationship rows are deleted unless the
-- confirmed RPC is called.
select public.get_family_leave_impact('00000000-0000-0000-0000-000000000004');
select public.leave_family('00000000-0000-0000-0000-000000000004');

-- 5. Cancellation of destructive leave:
-- Expected: after the failing leave_family(...) call, all family_members,
-- family_relationships, legacy_family_members and family_groups rows for that
-- family remain unchanged.
select
  (select count(*) from public.family_members where family_id = '00000000-0000-0000-0000-000000000003') as members,
  public.family_tree_remaining_summary('00000000-0000-0000-0000-000000000003') as tree_data,
  exists (
    select 1 from public.family_groups
    where id = '00000000-0000-0000-0000-000000000003'
  ) as family_still_exists;

-- 6. Confirmed destructive leave:
-- Expected: leave_family_confirmed(...) removes the last membership and deletes
-- only that family's pending invites, relationship/tree rows, legacy rows, and
-- family_groups row. It must not delete vaults, normal memories, users, or
-- storage objects.
select public.leave_family_confirmed('00000000-0000-0000-0000-000000000005');

-- 7. Concurrent requests:
-- Expected: two simultaneous calls for the same family serialize via advisory
-- locks. One should complete first; the other should either see the family as
-- already left/deleted or return the normal membership error, not partially
-- delete unrelated data.
-- Manual test: run case 6 in two SQL tabs at the same time for a staging family.

-- 8. Unrelated family data untouched:
-- Expected: counts for an unrelated control family are identical before and
-- after all destructive staging tests.
select
  (select count(*) from public.family_members where family_id = '00000000-0000-0000-0000-000000000099') as control_members,
  public.family_tree_remaining_summary('00000000-0000-0000-0000-000000000099') as control_tree_data,
  exists (
    select 1 from public.family_groups
    where id = '00000000-0000-0000-0000-000000000099'
  ) as control_family_exists;
