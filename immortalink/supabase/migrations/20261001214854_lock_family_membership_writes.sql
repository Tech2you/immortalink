-- Membership is admitted by invite/create RPCs, never by knowing a family UUID.
-- SECURITY DEFINER join/leave/primary/successor functions retain their grants.
revoke insert, update, delete, truncate, references, trigger
  on public.family_members from public, anon, authenticated;

drop policy if exists "join family as self" on public.family_members;
drop policy if exists family_members_insert_self on public.family_members;
drop policy if exists "update self membership" on public.family_members;
drop policy if exists family_members_update_self on public.family_members;
drop policy if exists family_members_delete_self on public.family_members;

-- Member reads continue through the existing family-scoped SELECT policy.
grant select on public.family_members to authenticated;
