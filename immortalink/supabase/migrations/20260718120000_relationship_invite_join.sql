-- Relationship-tree invitations do not require a visual slot. The invite is
-- linked into family_relationships and is replaced with the joining vault.

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
  v_existing_family_id uuid;
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
    into v_vault_id, v_existing_family_id
    from public.vaults
   where owner_id = v_user_id
   limit 1
   for update;

  if v_vault_id is null then
    raise exception 'No vault found for this account';
  end if;

  if v_existing_family_id is not null
     and v_existing_family_id <> v_invite.family_id then
    raise exception 'This vault already belongs to another family';
  end if;

  update public.vaults
     set family_id = v_invite.family_id
   where id = v_vault_id;

  update public.family_members
     set role = 'member',
         slot_key = coalesce(slot_key, v_invite.slot_key)
   where family_id = v_invite.family_id
     and user_id = v_user_id;

  if not found then
    insert into public.family_members (
      family_id,
      user_id,
      slot_key,
      role,
      joined_at
    ) values (
      v_invite.family_id,
      v_user_id,
      v_invite.slot_key,
      'member',
      now()
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
