-- New writes only. Existing family history is not reinterpreted or repaired.
create table family_access.relationship_requests (
  family_id uuid not null references public.family_groups(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  payload_hash bytea not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (family_id, actor_id, request_id)
);
create index relationship_requests_actor_idx on family_access.relationship_requests(actor_id);
alter table family_access.relationship_requests enable row level security;
revoke all on family_access.relationship_requests from public, anon, authenticated;

create function family_access.assert_relationship_node(p_family uuid, p_type text, p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_id is null or p_type is null or not (
    (p_type = 'vault' and exists (
      select 1 from public.vaults v join public.family_members m on m.user_id = v.owner_id
      where v.id = p_id and m.family_id = p_family)) or
    (p_type = 'legacy' and exists (
      select 1 from public.legacy_family_members l where l.id = p_id and l.family_id = p_family)) or
    (p_type = 'invite' and exists (
      select 1 from public.family_invites i where i.id = p_id and i.family_id = p_family
      and i.used_at is null and i.expires_at > now()))
  ) then
    raise exception 'RELATIONSHIP_PERSON_UNAVAILABLE' using errcode = '22023';
  end if;
end;
$$;

create function family_access.guard_relationship()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cycle boolean;
begin
  perform family_access.assert_relationship_node(new.family_id, new.parent_type, new.parent_id);
  perform family_access.assert_relationship_node(new.family_id, new.child_type, new.child_id);
  if new.relationship_kind is null or new.relationship_kind not in ('parent_child','sibling','spouse') then
    raise exception 'INVALID_RELATIONSHIP_KIND' using errcode = '22023';
  end if;
  if new.parent_type = new.child_type and new.parent_id = new.child_id then
    raise exception 'RELATIONSHIP_SELF_LINK' using errcode = '22023';
  end if;
  if new.relationship_kind = 'parent_child' then
    with recursive descendants(node_type, node_id) as (
      select new.child_type, new.child_id
      union
      select r.child_type, r.child_id from public.family_relationships r
      join descendants d on r.parent_type = d.node_type and r.parent_id = d.node_id
      where r.family_id = new.family_id and r.relationship_kind = 'parent_child'
        and r.id <> new.id
    ) select exists(select 1 from descendants where node_type = new.parent_type and node_id = new.parent_id)
      into v_cycle;
    if v_cycle then
      raise exception 'RELATIONSHIP_ANCESTRY_CYCLE' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

-- Same lock order as family admission/media writes, including invite acceptance.
create trigger relationship_statement_lock before insert or update or delete
on public.family_relationships for each statement execute function content_safety.lock_media_statement();
create trigger relationship_integrity before insert or update on public.family_relationships
for each row execute function family_access.guard_relationship();

create function family_access.add_relationship(p_family uuid, p_first jsonb, p_second jsonb, p_kind text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.family_relationships(family_id,parent_type,parent_id,child_type,child_id,relationship_kind)
  select p_family,p_first->>'type',(p_first->>'id')::uuid,p_second->>'type',(p_second->>'id')::uuid,p_kind
  where not exists (
    select 1 from public.family_relationships r where r.family_id = p_family and r.relationship_kind = p_kind
    and ((r.parent_type = p_first->>'type' and r.parent_id = (p_first->>'id')::uuid
      and r.child_type = p_second->>'type' and r.child_id = (p_second->>'id')::uuid)
    or (p_kind in ('sibling','spouse') and r.child_type = p_first->>'type'
      and r.child_id = (p_first->>'id')::uuid and r.parent_type = p_second->>'type'
      and r.parent_id = (p_second->>'id')::uuid))
  );
end;
$$;

create function public.create_family_relative(p_family_id uuid, p_request_id uuid, p_request jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_actor uuid := auth.uid();
  v_saved family_access.relationship_requests%rowtype;
  v_anchor jsonb := p_request->'anchor';
  v_person jsonb;
  v_node jsonb;
  v_other jsonb := p_request->'other_parent';
  v_kind text := p_request->>'relation';
  v_mode text := p_request->>'mode';
  v_gap integer := coalesce((p_request->>'gap')::integer,0);
  v_id uuid;
  v_viewer uuid;
  v_name text;
  v_code text;
  v_expires timestamptz;
  v_result jsonb;
  v_array text;
begin
  perform content_safety.media_lifecycle_lock();
  if v_actor is null or not exists(select 1 from public.family_members
    where family_id = p_family_id and user_id = v_actor) then
    raise exception 'Not a family member' using errcode = '42501';
  end if;
  if p_request_id is null or p_request is null or jsonb_typeof(p_request) <> 'object'
    or octet_length(p_request::text) > 65536 then
    raise exception 'INVALID_RELATIONSHIP_REQUEST' using errcode = '22023';
  end if;
  select * into v_saved from family_access.relationship_requests
    where family_id = p_family_id and actor_id = v_actor and request_id = p_request_id;
  if found then
    if v_saved.payload_hash <> sha256(convert_to(p_request::text,'UTF8')) then
      raise exception 'RELATIONSHIP_RETRY_CHANGED' using errcode = '22023';
    end if;
    return v_saved.result;
  end if;
  perform public.everroot_assert_family_writable(p_family_id);
  if v_kind is null or v_kind not in ('parent','child','sibling','spouse')
    or v_mode is null or v_mode not in ('legacy','invite') or v_gap not between 0 and 2
    or (v_gap > 0 and v_kind not in ('parent','child')) then
    raise exception 'INVALID_RELATIONSHIP_REQUEST' using errcode = '22023';
  end if;
  perform family_access.assert_relationship_node(p_family_id,v_anchor->>'type',(v_anchor->>'id')::uuid);
  foreach v_array in array array['shared_parents','partners','children'] loop
    if jsonb_typeof(coalesce(p_request->v_array,'[]'::jsonb)) <> 'array'
      or jsonb_array_length(coalesce(p_request->v_array,'[]'::jsonb)) > 500 then
      raise exception 'INVALID_RELATIONSHIP_REQUEST' using errcode = '22023';
    end if;
    for v_node in select value from jsonb_array_elements(coalesce(p_request->v_array,'[]'::jsonb)) loop
      perform family_access.assert_relationship_node(p_family_id,v_node->>'type',(v_node->>'id')::uuid);
    end loop;
  end loop;
  -- Only recorded parents of the focus can be selected as shared parents.
  for v_node in select value from jsonb_array_elements(coalesce(p_request->'shared_parents','[]'::jsonb)) loop
    if v_kind <> 'sibling' or not exists (
      select 1 from public.family_relationships where family_id = p_family_id and relationship_kind = 'parent_child'
      and parent_type = v_node->>'type' and parent_id = (v_node->>'id')::uuid
      and child_type = v_anchor->>'type' and child_id = (v_anchor->>'id')::uuid
    ) then raise exception 'INVALID_SHARED_PARENT' using errcode = '22023'; end if;
  end loop;
  if (v_kind <> 'parent' and jsonb_array_length(coalesce(p_request->'partners','[]'::jsonb)) > 0)
    or (v_kind not in ('parent','spouse') and jsonb_array_length(coalesce(p_request->'children','[]'::jsonb)) > 0)
    or (v_kind <> 'child' and v_other is not null and v_other <> 'null'::jsonb) then
    raise exception 'INVALID_RELATIONSHIP_REQUEST' using errcode = '22023';
  end if;
  if v_gap > 0 then
    for i in 1..v_gap loop
      v_name := case when v_kind = 'parent' then
        case when i = 1 then 'Parent not added yet' else 'Grandparent not added yet' end
        else case when i = 1 then 'Child not added yet' else 'Grandchild not added yet' end end;
      insert into public.legacy_family_members(family_id,name,display_name,created_by)
        values(p_family_id,v_name,v_name,v_actor) returning id into v_id;
      v_node := jsonb_build_object('type','legacy','id',v_id);
      if v_kind = 'parent' then perform family_access.add_relationship(p_family_id,v_node,v_anchor,'parent_child');
      else perform family_access.add_relationship(p_family_id,v_anchor,v_node,'parent_child'); end if;
      v_anchor := v_node;
    end loop;
  end if;
  if v_mode = 'legacy' then
    v_name := btrim(coalesce(p_request->>'name',''));
    if v_name = '' or length(v_name) > 200 or length(coalesce(p_request->>'about','')) > 20000 then
      raise exception 'INVALID_RELATIVE_DETAILS' using errcode = '22023';
    end if;
    insert into public.legacy_family_members(family_id,name,display_name,birth_year,death_year,created_by,about_me_text)
      values(p_family_id,v_name,null,(p_request->>'birth_year')::integer,(p_request->>'death_year')::integer,
      v_actor,nullif(btrim(p_request->>'about'),'')) returning id into v_id;
    v_person := jsonb_build_object('type','legacy','id',v_id);
    if nullif(btrim(p_request->>'about'),'') is not null then
      insert into public.legacy_memories(legacy_member_id,life_stage,prompt_key,prompt_text,body,family_id)
        values(v_id,'mid','about_me','About me',btrim(p_request->>'about'),p_family_id);
    end if;
  else
    select id into v_viewer from public.vaults where owner_id = v_actor order by id limit 1;
    if v_viewer is null then raise exception 'No vault found' using errcode = '22023'; end if;
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,16));
    v_expires := now() + interval '7 days';
    insert into public.family_invites(family_id,created_by,invite_code,expires_at,inviter_vault_id,slot_key)
      values(p_family_id,v_actor,v_code,v_expires,v_viewer,null) returning id into v_id;
    v_person := jsonb_build_object('type','invite','id',v_id);
  end if;
  if v_kind = 'parent' then perform family_access.add_relationship(p_family_id,v_person,v_anchor,'parent_child');
  elsif v_kind = 'child' then perform family_access.add_relationship(p_family_id,v_anchor,v_person,'parent_child');
  elsif v_kind = 'spouse' then perform family_access.add_relationship(p_family_id,v_anchor,v_person,'spouse');
  elsif jsonb_array_length(coalesce(p_request->'shared_parents','[]'::jsonb)) = 0 then
    perform family_access.add_relationship(p_family_id,v_anchor,v_person,'sibling');
  else
    for v_node in select value from jsonb_array_elements(p_request->'shared_parents') loop
      perform family_access.add_relationship(p_family_id,v_node,v_person,'parent_child');
    end loop;
  end if;
  for v_node in select value from jsonb_array_elements(coalesce(p_request->'partners','[]'::jsonb)) loop
    perform family_access.add_relationship(p_family_id,v_person,v_node,'spouse');
  end loop;
  for v_node in select value from jsonb_array_elements(coalesce(p_request->'children','[]'::jsonb)) loop
    perform family_access.add_relationship(p_family_id,v_person,v_node,'parent_child');
  end loop;
  if v_other is not null and v_other <> 'null'::jsonb then
    if v_other->>'type' = 'placeholder' then
      insert into public.legacy_family_members(family_id,name,display_name,created_by)
        values(p_family_id,'Parent not added yet','Parent not added yet',v_actor) returning id into v_id;
      v_other := jsonb_build_object('type','legacy','id',v_id);
    end if;
    perform family_access.add_relationship(p_family_id,v_other,v_person,'parent_child');
  end if;
  v_result := v_person || jsonb_build_object('invite_code',v_code,'expires_at',v_expires);
  insert into family_access.relationship_requests(family_id,actor_id,request_id,payload_hash,result)
    values(p_family_id,v_actor,p_request_id,sha256(convert_to(p_request::text,'UTF8')),v_result);
  return v_result;
end;
$$;

revoke all on function family_access.assert_relationship_node(uuid,text,uuid) from public,anon,authenticated;
revoke all on function family_access.guard_relationship() from public,anon,authenticated;
revoke all on function family_access.add_relationship(uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function public.create_family_relative(uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_family_relative(uuid,uuid,jsonb) to authenticated;
