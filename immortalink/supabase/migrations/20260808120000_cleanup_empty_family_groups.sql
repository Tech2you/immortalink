-- Safe empty-family cleanup.
--
-- Automatic cleanup is intentionally conservative:
-- - a family with any real user membership is never deleted;
-- - a family with relationship edges, family links, legacy people, or
--   legacy-family data is never silently deleted;
-- - pending invites alone are safe to remove with an otherwise empty family;
-- - explicit confirmed cleanup is required before deleting a legacy-only tree.

create or replace function public.count_family_rows_if_present(
  p_table_name text,
  p_family_id uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  if p_family_id is null then
    return 0;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = p_table_name
      and column_name = 'family_id'
  ) then
    execute format('select count(*) from public.%I where family_id = $1', p_table_name)
      into v_count
      using p_family_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.count_family_rows_if_present(text, uuid) from public;
grant execute on function public.count_family_rows_if_present(text, uuid) to service_role;

create or replace function public.family_tree_remaining_summary(p_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_pending_invites integer;
  v_relationships integer;
  v_family_links integer;
  v_legacy_people integer;
  v_legacy_memories integer;
  v_legacy_memory_voice_notes integer;
  v_legacy_memory_chunks integer;
  v_legacy_memory_photos integer;
  v_legacy_member_photos integer;
  v_legacy_vault_about_photos integer;
  v_legacy_vault_core_voice_note integer;
  v_has_meaningful_data boolean;
begin
  v_pending_invites := public.count_family_rows_if_present('family_invites', p_family_id);
  v_relationships := public.count_family_rows_if_present('family_relationships', p_family_id);
  v_family_links := public.count_family_rows_if_present('family_links', p_family_id);
  v_legacy_people := public.count_family_rows_if_present('legacy_family_members', p_family_id);
  v_legacy_memories := public.count_family_rows_if_present('legacy_memories', p_family_id);
  v_legacy_memory_voice_notes := public.count_family_rows_if_present('legacy_memory_voice_notes', p_family_id);
  v_legacy_memory_chunks := public.count_family_rows_if_present('legacy_memory_chunks', p_family_id);
  v_legacy_memory_photos := public.count_family_rows_if_present('legacy_memory_photos', p_family_id);
  v_legacy_member_photos := public.count_family_rows_if_present('legacy_member_photos', p_family_id);
  v_legacy_vault_about_photos := public.count_family_rows_if_present('legacy_vault_about_photos', p_family_id);
  v_legacy_vault_core_voice_note := public.count_family_rows_if_present('legacy_vault_core_voice_note', p_family_id);

  v_has_meaningful_data := (
    v_relationships
    + v_family_links
    + v_legacy_people
    + v_legacy_memories
    + v_legacy_memory_voice_notes
    + v_legacy_memory_chunks
    + v_legacy_memory_photos
    + v_legacy_member_photos
    + v_legacy_vault_about_photos
    + v_legacy_vault_core_voice_note
  ) > 0;

  return jsonb_build_object(
    'has_meaningful_tree_data', v_has_meaningful_data,
    'pending_invites', v_pending_invites,
    'relationships', v_relationships,
    'family_links', v_family_links,
    'legacy_people', v_legacy_people,
    'legacy_memories', v_legacy_memories,
    'legacy_memory_voice_notes', v_legacy_memory_voice_notes,
    'legacy_memory_chunks', v_legacy_memory_chunks,
    'legacy_memory_photos', v_legacy_memory_photos,
    'legacy_member_photos', v_legacy_member_photos,
    'legacy_vault_about_photos', v_legacy_vault_about_photos,
    'legacy_vault_core_voice_note', v_legacy_vault_core_voice_note
  );
end;
$$;

revoke all on function public.family_tree_remaining_summary(uuid) from public;
grant execute on function public.family_tree_remaining_summary(uuid) to service_role;

create or replace function public.cleanup_empty_family_group(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_summary jsonb;
begin
  if p_family_id is null then
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  perform 1
    from public.family_groups
   where id = p_family_id
   for update;

  if not found then
    return;
  end if;

  if exists (
    select 1
    from public.family_members
    where family_id = p_family_id
  ) then
    return;
  end if;

  v_summary := public.family_tree_remaining_summary(p_family_id);

  -- Legacy/tree data requires explicit confirmation, so silent cleanup stops.
  if coalesce((v_summary->>'has_meaningful_tree_data')::boolean, false) then
    return;
  end if;

  -- Do not delete vaults or memories. Clear only a stale home-family pointer.
  update public.vaults
     set family_id = null
   where family_id = p_family_id;

  begin
    delete from public.family_groups fg
     where fg.id = p_family_id
       and not exists (
         select 1
         from public.family_members fm
         where fm.family_id = p_family_id
       )
       and not coalesce((
         public.family_tree_remaining_summary(p_family_id)
           ->> 'has_meaningful_tree_data'
       )::boolean, false);
  exception
    when foreign_key_violation then
      null;
  end;
end;
$$;

revoke all on function public.cleanup_empty_family_group(uuid) from public;
grant execute on function public.cleanup_empty_family_group(uuid) to service_role;

create or replace function public.destroy_empty_family_group_tree(p_family_id uuid)
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

  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  perform 1
    from public.family_groups
   where id = p_family_id
   for update;

  if not found then
    return;
  end if;

  if exists (
    select 1
    from public.family_members
    where family_id = p_family_id
  ) then
    raise exception 'Family still has real members'
      using errcode = 'P0001',
            detail = 'ERR_FAMILY_NOT_EMPTY';
  end if;

  -- Do not delete vaults, normal memories, normal memory media, users, or auth
  -- rows. This clears only the now-empty family's tree/legacy scaffolding.
  update public.vaults
     set family_id = null
   where family_id = p_family_id;

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

  delete from public.family_groups fg
   where fg.id = p_family_id
     and not exists (
       select 1
       from public.family_members fm
       where fm.family_id = p_family_id
     );
end;
$$;

revoke all on function public.destroy_empty_family_group_tree(uuid) from public;
grant execute on function public.destroy_empty_family_group_tree(uuid) to service_role;

create or replace function public.get_family_leave_impact(p_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_member_count integer;
  v_is_member boolean;
  v_summary jsonb;
  v_is_last_member boolean;
  v_requires_confirmation boolean;
begin
  if p_family_id is null then
    raise exception 'Family id is required' using errcode = '22004';
  end if;

  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select count(*)
    into v_member_count
    from public.family_members
   where family_id = p_family_id;

  select exists (
    select 1
    from public.family_members
    where family_id = p_family_id
      and user_id = v_user_id
  )
    into v_is_member;

  if not v_is_member then
    raise exception 'You are not a member of this family' using errcode = '42501';
  end if;

  v_summary := public.family_tree_remaining_summary(p_family_id);
  v_is_last_member := v_member_count = 1;
  v_requires_confirmation := v_is_last_member
    and coalesce((v_summary->>'has_meaningful_tree_data')::boolean, false);

  return jsonb_build_object(
    'family_id', p_family_id,
    'member_count', v_member_count,
    'is_last_real_member', v_is_last_member,
    'requires_destructive_confirmation', v_requires_confirmation,
    'message', case
      when v_requires_confirmation then
        'You are the last member of this family. Leaving will permanently delete this family tree, including its legacy profiles and relationships. Do you want to continue?'
      else null
    end,
    'tree_data', v_summary
  );
end;
$$;

revoke all on function public.get_family_leave_impact(uuid) from public;
grant execute on function public.get_family_leave_impact(uuid) to authenticated;

create or replace function public.lock_family_membership_family()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' or tg_op = 'UPDATE' then
    if new.family_id is not null then
      perform pg_advisory_xact_lock(hashtext(new.family_id::text));
    end if;
  elsif tg_op = 'DELETE' and old.family_id is not null then
    perform pg_advisory_xact_lock(hashtext(old.family_id::text));
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists family_members_lock_family_before_write
  on public.family_members;
drop trigger if exists family_members_lock_family_before_insert_update
  on public.family_members;
drop trigger if exists family_members_lock_family_before_delete
  on public.family_members;
create trigger family_members_lock_family_before_insert_update
  before insert or update of family_id on public.family_members
  for each row
  execute function public.lock_family_membership_family();
create trigger family_members_lock_family_before_delete
  before delete on public.family_members
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

create or replace function public.leave_family(p_family_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_vault_id uuid;
  v_primary_family_id uuid;
  v_next_family_id uuid;
  v_member_count integer;
  v_summary jsonb;
begin
  if p_family_id is null then
    raise exception 'Family id is required' using errcode = '22004';
  end if;

  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  select id, family_id
    into v_vault_id, v_primary_family_id
    from public.vaults
   where owner_id = v_user_id
   limit 1
   for update;

  if v_vault_id is null then
    raise exception 'No vault found for this account';
  end if;

  if not exists (
    select 1
    from public.family_members
    where family_id = p_family_id
      and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family' using errcode = '42501';
  end if;

  perform 1
    from public.family_members
   where family_id = p_family_id
   for update;

  select count(*)
    into v_member_count
    from public.family_members
   where family_id = p_family_id;

  v_summary := public.family_tree_remaining_summary(p_family_id);

  if v_member_count = 1
     and coalesce((v_summary->>'has_meaningful_tree_data')::boolean, false) then
    raise exception 'Leaving this family requires confirmation'
      using errcode = 'P0001',
            detail = 'ERR_LEAVE_FAMILY_REQUIRES_CONFIRMATION',
            hint = 'Call get_family_leave_impact first, show the warning, then call leave_family_confirmed if the user confirms.';
  end if;

  delete from public.family_relationships
   where family_id = p_family_id
     and (
       (parent_type = 'vault' and parent_id = v_vault_id)
       or (child_type = 'vault' and child_id = v_vault_id)
     );

  delete from public.family_members
   where family_id = p_family_id
     and user_id = v_user_id;

  if v_primary_family_id = p_family_id then
    select family_id
      into v_next_family_id
      from public.family_members
     where user_id = v_user_id
     order by joined_at nulls last, family_id
     limit 1;

    update public.family_members
       set is_primary = (family_id = v_next_family_id)
     where user_id = v_user_id;

    update public.vaults
       set family_id = v_next_family_id
     where id = v_vault_id;
  end if;

  return v_next_family_id;
end;
$$;

revoke all on function public.leave_family(uuid) from public;
grant execute on function public.leave_family(uuid) to authenticated;

create or replace function public.leave_family_confirmed(p_family_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_vault_id uuid;
  v_primary_family_id uuid;
  v_next_family_id uuid;
  v_member_count integer;
begin
  if p_family_id is null then
    raise exception 'Family id is required' using errcode = '22004';
  end if;

  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_family_id::text));

  select id, family_id
    into v_vault_id, v_primary_family_id
    from public.vaults
   where owner_id = v_user_id
   limit 1
   for update;

  if v_vault_id is null then
    raise exception 'No vault found for this account';
  end if;

  if not exists (
    select 1
    from public.family_members
    where family_id = p_family_id
      and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family' using errcode = '42501';
  end if;

  perform 1
    from public.family_members
   where family_id = p_family_id
   for update;

  select count(*)
    into v_member_count
    from public.family_members
   where family_id = p_family_id;

  if v_member_count > 1 then
    return public.leave_family(p_family_id);
  end if;

  delete from public.family_members
   where family_id = p_family_id
     and user_id = v_user_id;

  if v_primary_family_id = p_family_id then
    select family_id
      into v_next_family_id
      from public.family_members
     where user_id = v_user_id
     order by joined_at nulls last, family_id
     limit 1;

    update public.family_members
       set is_primary = (family_id = v_next_family_id)
     where user_id = v_user_id;

    update public.vaults
       set family_id = v_next_family_id
     where id = v_vault_id;
  end if;

  perform public.destroy_empty_family_group_tree(p_family_id);

  return v_next_family_id;
end;
$$;

revoke all on function public.leave_family_confirmed(uuid) from public;
grant execute on function public.leave_family_confirmed(uuid) to authenticated;
