-- Harden the highest-confidence SECURITY DEFINER RPC exposure findings.
--
-- These changes avoid broad rewrites:
-- - app-facing RPCs remain available where current Flutter uses them;
-- - unused get_family_layout is no longer callable through the public API;
-- - membership helper calls cannot probe other users;
-- - create_legacy_relative now verifies the anchor belongs to the target family.

create or replace function public.is_family_member(
  p_family_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_user_id = auth.uid()
    and exists (
      select 1
      from public.family_members fm
      where fm.family_id = p_family_id
        and fm.user_id = p_user_id
    );
$$;

revoke all on function public.is_family_member(uuid, uuid)
  from public, anon;
grant execute on function public.is_family_member(uuid, uuid)
  to authenticated, service_role;

revoke all on function public.get_family_layout(uuid)
  from public, anon, authenticated;
grant execute on function public.get_family_layout(uuid)
  to service_role;

create or replace function public.create_legacy_relative(
  p_family_id uuid,
  p_anchor_type text,
  p_anchor_id uuid,
  p_relation text,
  p_name text,
  p_display_name text default null,
  p_birth_year integer default null,
  p_death_year integer default null,
  p_about_me_text text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_legacy_member_id uuid;
  v_parent_type text;
  v_parent_id uuid;
  v_child_type text;
  v_child_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not public.can_access_legacy_family(p_family_id) then
    raise exception 'You are not a member of this family' using errcode = '42501';
  end if;

  if trim(coalesce(p_name, '')) = '' then
    raise exception 'Name is required' using errcode = '22023';
  end if;

  if p_anchor_type not in ('vault', 'legacy') then
    raise exception 'Invalid anchor type' using errcode = '22023';
  end if;

  if p_relation not in ('parent', 'child', 'spouse', 'sibling') then
    raise exception 'Invalid relation' using errcode = '22023';
  end if;

  if p_anchor_type = 'vault' and not exists (
    select 1
    from public.vaults v
    join public.family_members fm
      on fm.user_id = v.owner_id
     and fm.family_id = p_family_id
    where v.id = p_anchor_id
  ) then
    raise exception 'Anchor vault is not in this family' using errcode = '42501';
  end if;

  if p_anchor_type = 'legacy' and not exists (
    select 1
    from public.legacy_family_members lfm
    where lfm.id = p_anchor_id
      and lfm.family_id = p_family_id
  ) then
    raise exception 'Anchor legacy profile is not in this family' using errcode = '42501';
  end if;

  insert into public.legacy_family_members (
    family_id,
    slot_key,
    name,
    display_name,
    birth_year,
    death_year,
    created_by,
    about_me_text
  )
  values (
    p_family_id,
    null,
    trim(p_name),
    nullif(trim(coalesce(p_display_name, '')), ''),
    p_birth_year,
    p_death_year,
    v_me,
    nullif(trim(coalesce(p_about_me_text, '')), '')
  )
  returning id into v_legacy_member_id;

  if p_relation = 'parent' then
    v_parent_type := 'legacy';
    v_parent_id := v_legacy_member_id;
    v_child_type := p_anchor_type;
    v_child_id := p_anchor_id;

    insert into public.family_relationships (
      family_id,
      parent_type,
      parent_id,
      child_type,
      child_id,
      relationship_kind
    )
    values (
      p_family_id,
      v_parent_type,
      v_parent_id,
      v_child_type,
      v_child_id,
      'parent_child'
    );

  elsif p_relation = 'child' then
    v_parent_type := p_anchor_type;
    v_parent_id := p_anchor_id;
    v_child_type := 'legacy';
    v_child_id := v_legacy_member_id;

    insert into public.family_relationships (
      family_id,
      parent_type,
      parent_id,
      child_type,
      child_id,
      relationship_kind
    )
    values (
      p_family_id,
      v_parent_type,
      v_parent_id,
      v_child_type,
      v_child_id,
      'parent_child'
    );

  elsif p_relation = 'spouse' then
    insert into public.family_relationships (
      family_id,
      parent_type,
      parent_id,
      child_type,
      child_id,
      relationship_kind
    )
    values
      (
        p_family_id,
        p_anchor_type,
        p_anchor_id,
        'legacy',
        v_legacy_member_id,
        'spouse'
      ),
      (
        p_family_id,
        'legacy',
        v_legacy_member_id,
        p_anchor_type,
        p_anchor_id,
        'spouse'
      );

  elsif p_relation = 'sibling' then
    insert into public.family_relationships (
      family_id,
      parent_type,
      parent_id,
      child_type,
      child_id,
      relationship_kind
    )
    select
      p_family_id,
      fr.parent_type,
      fr.parent_id,
      'legacy',
      v_legacy_member_id,
      'parent_child'
    from public.family_relationships fr
    where fr.family_id = p_family_id
      and fr.relationship_kind = 'parent_child'
      and fr.child_type = p_anchor_type
      and fr.child_id = p_anchor_id;

    if not exists (
      select 1
      from public.family_relationships fr
      where fr.family_id = p_family_id
        and fr.relationship_kind = 'parent_child'
        and fr.child_type = 'legacy'
        and fr.child_id = v_legacy_member_id
    ) then
      raise exception 'Anchor person has no parents to derive sibling relationship from'
        using errcode = '22023';
    end if;
  end if;

  if trim(coalesce(p_about_me_text, '')) <> '' then
    insert into public.legacy_memories (
      legacy_member_id,
      life_stage,
      prompt_key,
      prompt_text,
      body,
      family_id
    )
    values (
      v_legacy_member_id,
      'mid',
      'about_me',
      'About me',
      trim(p_about_me_text),
      p_family_id
    );
  end if;

  return v_legacy_member_id;
end;
$$;

revoke all on function public.create_legacy_relative(
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  integer,
  integer,
  text
) from public, anon;
grant execute on function public.create_legacy_relative(
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  integer,
  integer,
  text
) to authenticated;

comment on function public.create_legacy_relative(
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  integer,
  integer,
  text
) is
  'Creates a legacy relative only when the caller is a member of the family and the anchor belongs to that same family.';
