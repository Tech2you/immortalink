-- Launch with one family membership per account. Keep every existing
-- membership, including existing multi-family accounts, and leave the
-- existing invitation, home-family and family-leave behavior intact.
--
-- A table trigger covers both invitation RPCs, family creation and any future
-- admission path. It adds a restriction; it grants no membership permissions.
create schema if not exists family_access;
revoke all on schema family_access from public, anon, authenticated;

create or replace function family_access.guard_single_family_admission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Switching home family or editing an existing member is still supported.
  if tg_op = 'UPDATE'
     and new.family_id is not distinct from old.family_id
     and new.user_id is not distinct from old.user_id then
    return new;
  end if;

  -- Serialize competing admissions for the same account, including accounts
  -- with no membership row to lock yet. The subsequent query gets a fresh
  -- snapshot under the READ COMMITTED isolation used by the Data API/RPCs.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('family-membership-launch:' || new.user_id::text, 0)
  );

  -- INSERT ... ON CONFLICT fires BEFORE INSERT even for existing rows. Keep
  -- same-family invites/upserts working for grandfathered multi-family users.
  if exists (
    select 1 from public.family_members fm
    where fm.user_id = new.user_id and fm.family_id = new.family_id
  ) then
    return new;
  end if;

  if exists (
    select 1 from public.family_members fm
    where fm.user_id = new.user_id
  ) then
    raise exception 'FAMILY_MEMBERSHIP_LIMIT'
      using errcode = 'P0001',
            detail = 'You already belong to a family. Joining another family is not available yet.';
  end if;

  return new;
end;
$function$;

-- Trigger-only helper in a non-API schema. It must not become a callable RPC.
revoke all on function family_access.guard_single_family_admission()
  from public, anon, authenticated, service_role;

create trigger family_members_single_family_launch_guard
before insert or update of family_id, user_id on public.family_members
for each row execute function family_access.guard_single_family_admission();
