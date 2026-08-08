-- Remove family groups only after the last real user membership is gone.
-- This keeps cleanup server-side and protects populated shared families from
-- client-side race conditions or incomplete cleanup paths.

create or replace function public.cleanup_empty_family_group(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table text;
begin
  if p_family_id is null then
    return;
  end if;

  -- Serialize membership cleanup for this family. This avoids a simultaneous
  -- join/leave transaction observing a half-cleaned family tree.
  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  -- If the group is already gone there is nothing left to clean.
  perform 1
    from public.family_groups
   where id = p_family_id
   for update;

  if not found then
    return;
  end if;

  -- A family with any real user membership is still active.
  if exists (
    select 1
      from public.family_members
     where family_id = p_family_id
  ) then
    return;
  end if;

  -- Do not delete vaults or memories. A stale home-family pointer can be
  -- cleared safely once the family has no memberships.
  update public.vaults
     set family_id = null
   where family_id = p_family_id;

  -- These rows are only family-tree scaffolding for an empty family:
  -- pending invites, relationship edges, and family-owned legacy profile data.
  foreach v_table in array array[
    'family_invites',
    'family_relationships',
    'family_links',
    'legacy_memory_voice_notes',
    'legacy_memory_chunks',
    'legacy_memory_photos',
    'legacy_member_photos',
    'legacy_vault_about_photos',
    'legacy_vault_core_voice_note',
    'legacy_memories',
    'legacy_family_members'
  ] loop
    if exists (
      select 1
        from information_schema.columns
       where table_schema = 'public'
         and table_name = v_table
         and column_name = 'family_id'
    ) then
      execute format('delete from public.%I where family_id = $1', v_table)
        using p_family_id;
    end if;
  end loop;

  -- Delete the group last, and re-check membership in the same statement.
  -- If an unknown table still references this group, do not block the user's
  -- membership removal; leave the family row in place for manual review.
  begin
    delete from public.family_groups fg
     where fg.id = p_family_id
       and not exists (
         select 1
           from public.family_members fm
          where fm.family_id = p_family_id
       );
  exception
    when foreign_key_violation then
      null;
  end;
end;
$$;

revoke all on function public.cleanup_empty_family_group(uuid) from public;
grant execute on function public.cleanup_empty_family_group(uuid) to service_role;

create or replace function public.lock_family_membership_family()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.family_id is not null then
    perform pg_advisory_xact_lock(hashtext(new.family_id::text));
  end if;

  return new;
end;
$$;

drop trigger if exists family_members_lock_family_before_write
  on public.family_members;
create trigger family_members_lock_family_before_write
  before insert or update of family_id on public.family_members
  for each row
  execute function public.lock_family_membership_family();

create or replace function public.cleanup_empty_family_group_after_membership_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.cleanup_empty_family_group(old.family_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.family_id is distinct from new.family_id then
    perform public.cleanup_empty_family_group(old.family_id);
  end if;

  return new;
end;
$$;

drop trigger if exists family_members_cleanup_empty_family_after_change
  on public.family_members;
create trigger family_members_cleanup_empty_family_after_change
  after delete or update of family_id on public.family_members
  for each row
  execute function public.cleanup_empty_family_group_after_membership_change();
