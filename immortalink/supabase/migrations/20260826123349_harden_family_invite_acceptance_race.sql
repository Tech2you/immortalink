set check_function_bodies = off;

create or replace function public.join_family_by_invite(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_invite_id uuid;
  v_family_id uuid;
  v_slot_key text;
  v_inviter uuid;
  v_inviter_vault_id uuid;
  v_me uuid := auth.uid();
  v_vault_id uuid;
  v_expires_at timestamptz;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  select
    id,
    family_id,
    slot_key,
    created_by,
    inviter_vault_id,
    expires_at
  into
    v_invite_id,
    v_family_id,
    v_slot_key,
    v_inviter,
    v_inviter_vault_id,
    v_expires_at
  from public.family_invites
  where upper(invite_code) = upper(btrim(p_invite_code))
    and used_at is null
    and (expires_at is null or expires_at > now())
  limit 1
  for update;

  if v_family_id is null then
    raise exception 'Invite code is invalid, expired, or already used';
  end if;

  select id
  into v_vault_id
  from public.vaults
  where owner_id = v_me
  limit 1;

  if v_vault_id is null then
    raise exception 'No vault found for your account';
  end if;

  if v_inviter_vault_id is null then
    select id
    into v_inviter_vault_id
    from public.vaults
    where owner_id = v_inviter
    limit 1;
  end if;

  insert into public.family_members (family_id, user_id, role, slot_key)
  values (v_family_id, v_me, 'member', v_slot_key)
  on conflict (family_id, user_id) do update
    set role = excluded.role,
        slot_key = excluded.slot_key;

  update public.vaults
  set family_id = v_family_id
  where id = v_vault_id;

  update public.family_invites
  set used_at = now(),
      used_by = v_me,
      used_by_vault_id = v_vault_id
  where id = v_invite_id
    and used_at is null;

  if not found then
    raise exception 'Invite code is invalid, expired, or already used';
  end if;

  insert into public.family_relationships (
    family_id,
    parent_type,
    parent_id,
    child_type,
    child_id,
    relationship_kind
  )
  select
    fr.family_id,
    'vault',
    v_vault_id,
    fr.child_type,
    fr.child_id,
    fr.relationship_kind
  from public.family_relationships fr
  where fr.family_id = v_family_id
    and fr.parent_type = 'invite'
    and fr.parent_id = v_invite_id
    and not exists (
      select 1
      from public.family_relationships x
      where x.family_id = fr.family_id
        and x.parent_type = 'vault'
        and x.parent_id = v_vault_id
        and x.child_type = fr.child_type
        and x.child_id = fr.child_id
        and coalesce(x.relationship_kind, '') = coalesce(fr.relationship_kind, '')
    );

  insert into public.family_relationships (
    family_id,
    parent_type,
    parent_id,
    child_type,
    child_id,
    relationship_kind
  )
  select
    fr.family_id,
    fr.parent_type,
    fr.parent_id,
    'vault',
    v_vault_id,
    fr.relationship_kind
  from public.family_relationships fr
  where fr.family_id = v_family_id
    and fr.child_type = 'invite'
    and fr.child_id = v_invite_id
    and not exists (
      select 1
      from public.family_relationships x
      where x.family_id = fr.family_id
        and x.parent_type = fr.parent_type
        and x.parent_id = fr.parent_id
        and x.child_type = 'vault'
        and x.child_id = v_vault_id
        and coalesce(x.relationship_kind, '') = coalesce(fr.relationship_kind, '')
    );

  if v_slot_key = 'spouse_1' and v_inviter_vault_id is not null then
    insert into public.family_relationships (
      family_id,
      parent_type,
      parent_id,
      child_type,
      child_id,
      relationship_kind
    )
    select
      v_family_id,
      'vault',
      v_inviter_vault_id,
      'vault',
      v_vault_id,
      'spouse'
    where not exists (
      select 1
      from public.family_relationships fr
      where fr.family_id = v_family_id
        and fr.relationship_kind = 'spouse'
        and (
          (
            fr.parent_type = 'vault'
            and fr.parent_id = v_inviter_vault_id
            and fr.child_type = 'vault'
            and fr.child_id = v_vault_id
          )
          or
          (
            fr.parent_type = 'vault'
            and fr.parent_id = v_vault_id
            and fr.child_type = 'vault'
            and fr.child_id = v_inviter_vault_id
          )
        )
    );
  end if;

  return v_family_id;
end;
$function$;

create or replace function public.join_family_by_relationship_invite(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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
     and used_at is null
     and expires_at > now()
   limit 1
   for update;

  if v_invite.id is null then
    raise exception 'Invite code is invalid, expired, or already used';
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
    select 1
    from public.family_members fm
    where fm.family_id = v_invite.family_id
      and fm.user_id = v_user_id
  ) then
    perform public.everroot_assert_can_add_family_member(
      v_invite.family_id,
      v_user_id
    );
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

  delete from public.family_invites
   where id = v_invite.id
     and used_at is null;

  if not found then
    raise exception 'Invite code is invalid, expired, or already used';
  end if;

  return v_invite.family_id;
end;
$function$;
