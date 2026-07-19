-- A vault keeps one primary/home family in vaults.family_id for backwards
-- compatibility, while family_members becomes the source of all memberships.

alter table public.family_members
  add column if not exists is_primary boolean not null default false;

-- Ensure every vault's existing family is represented as a membership.
insert into public.family_members (
  family_id,
  user_id,
  role,
  joined_at,
  is_primary
)
select
  v.family_id,
  v.owner_id,
  'member',
  now(),
  true
from public.vaults v
where v.family_id is not null
  and not exists (
    select 1
    from public.family_members fm
    where fm.family_id = v.family_id
      and fm.user_id = v.owner_id
  );

update public.family_members fm
set is_primary = true
from public.vaults v
where v.owner_id = fm.user_id
  and v.family_id = fm.family_id
  and v.family_id is not null;

-- Give membership-only users a primary tree when older data omitted one.
with ranked as (
  select
    family_id,
    user_id,
    row_number() over (
      partition by user_id
      order by joined_at nulls last, family_id
    ) as position
  from public.family_members
  where user_id not in (
    select owner_id from public.vaults where family_id is not null
  )
)
update public.family_members fm
set is_primary = true
from ranked r
where r.position = 1
  and r.family_id = fm.family_id
  and r.user_id = fm.user_id;

create unique index if not exists family_members_one_primary_per_user
  on public.family_members (user_id)
  where is_primary;

update public.vaults v
set family_id = fm.family_id
from public.family_members fm
where fm.user_id = v.owner_id
  and fm.is_primary
  and v.family_id is null;

create or replace function public.join_family_by_relationship_invite(
  p_invite_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_invite public.family_invites%rowtype;
  v_vault_id uuid;
  v_primary_family_id uuid;
  v_make_primary boolean;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into v_invite
    from public.family_invites
   where upper(invite_code) = upper(btrim(p_invite_code))
     and expires_at > now()
   limit 1
   for update;

  if v_invite.id is null then
    raise exception 'Invite code is invalid or expired';
  end if;

  select id, family_id
    into v_vault_id, v_primary_family_id
    from public.vaults
   where owner_id = v_user_id
   limit 1
   for update;

  if v_vault_id is null then
    raise exception 'No vault found for this account';
  end if;

  v_make_primary := v_primary_family_id is null;

  if v_make_primary then
    update public.family_members
       set is_primary = false
     where user_id = v_user_id;

    update public.vaults
       set family_id = v_invite.family_id
     where id = v_vault_id;
  end if;

  update public.family_members
     set role = case when role = 'owner' then role else 'member' end,
         slot_key = coalesce(slot_key, v_invite.slot_key),
         is_primary = case when v_make_primary then true else is_primary end
   where family_id = v_invite.family_id
     and user_id = v_user_id;

  if not found then
    insert into public.family_members (
      family_id,
      user_id,
      slot_key,
      role,
      joined_at,
      is_primary
    ) values (
      v_invite.family_id,
      v_user_id,
      v_invite.slot_key,
      'member',
      now(),
      v_make_primary
    );
  end if;

  update public.family_relationships
     set parent_type = 'vault',
         parent_id = v_vault_id
   where family_id = v_invite.family_id
     and parent_type = 'invite'
     and parent_id = v_invite.id;

  update public.family_relationships
     set child_type = 'vault',
         child_id = v_vault_id
   where family_id = v_invite.family_id
     and child_type = 'invite'
     and child_id = v_invite.id;

  delete from public.family_invites where id = v_invite.id;

  return v_invite.family_id;
end;
$$;

revoke all on function public.join_family_by_relationship_invite(text)
  from public;
grant execute on function public.join_family_by_relationship_invite(text)
  to authenticated;

create or replace function public.set_primary_family(p_family_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family';
  end if;

  update public.family_members
     set is_primary = (family_id = p_family_id)
   where user_id = v_user_id;

  update public.vaults
     set family_id = p_family_id
   where owner_id = v_user_id;

  return p_family_id;
end;
$$;

revoke all on function public.set_primary_family(uuid) from public;
grant execute on function public.set_primary_family(uuid) to authenticated;

drop function if exists public.leave_family(uuid);
create function public.leave_family(p_family_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_vault_id uuid;
  v_primary_family_id uuid;
  v_next_family_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

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
    select 1 from public.family_members
    where family_id = p_family_id and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this family';
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

-- Shared-family vault access is based on membership, not only the primary
-- family stored on the vault row.
create or replace function public.shares_family_with_vault(p_vault_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.vaults target
    join public.family_members target_membership
      on target_membership.user_id = target.owner_id
    join public.family_members viewer_membership
      on viewer_membership.family_id = target_membership.family_id
     and viewer_membership.user_id = auth.uid()
    where target.id = p_vault_id
  );
$$;

revoke all on function public.shares_family_with_vault(uuid) from public;
grant execute on function public.shares_family_with_vault(uuid)
  to authenticated;

drop policy if exists "multi-family members can view vaults" on public.vaults;
create policy "multi-family members can view vaults"
  on public.vaults
  for select
  to authenticated
  using (
    owner_id = auth.uid()
    or public.shares_family_with_vault(id)
  );

do $$
begin
  if to_regclass('public.memories') is not null then
    execute 'drop policy if exists "multi-family members can view memories" on public.memories';
    execute 'create policy "multi-family members can view memories" on public.memories for select to authenticated using (public.shares_family_with_vault(vault_id))';
  end if;
  if to_regclass('public.memory_chunks') is not null then
    execute 'drop policy if exists "multi-family members can view memory chunks" on public.memory_chunks';
    execute 'create policy "multi-family members can view memory chunks" on public.memory_chunks for select to authenticated using (public.shares_family_with_vault(vault_id))';
  end if;
  if to_regclass('public.vault_about_photos') is not null then
    execute 'drop policy if exists "multi-family members can view about photos" on public.vault_about_photos';
    execute 'create policy "multi-family members can view about photos" on public.vault_about_photos for select to authenticated using (public.shares_family_with_vault(vault_id))';
  end if;
  if to_regclass('public.vault_core_voice_note') is not null then
    execute 'drop policy if exists "multi-family members can view core voice" on public.vault_core_voice_note';
    execute 'create policy "multi-family members can view core voice" on public.vault_core_voice_note for select to authenticated using (public.shares_family_with_vault(vault_id))';
  end if;
  if to_regclass('public.memory_photos') is not null then
    execute 'drop policy if exists "multi-family members can view memory photos" on public.memory_photos';
    execute 'create policy "multi-family members can view memory photos" on public.memory_photos for select to authenticated using (exists (select 1 from public.memories m where m.id = memory_id and public.shares_family_with_vault(m.vault_id)))';
  end if;
  if to_regclass('public.memory_voice_notes') is not null then
    execute 'drop policy if exists "multi-family members can view memory voice" on public.memory_voice_notes';
    execute 'create policy "multi-family members can view memory voice" on public.memory_voice_notes for select to authenticated using (exists (select 1 from public.memories m where m.id = memory_id and public.shares_family_with_vault(m.vault_id)))';
  end if;
end
$$;
