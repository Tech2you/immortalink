-- Preserve retained contributions while removing deleted-account attribution.
create or replace function public.guard_media_reference_scope()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  r jsonb:=to_jsonb(new); previous jsonb; f uuid; v uuid; l uuid; m uuid;
  path text; buckets text[]; key text;
begin
  if coalesce(auth.jwt()->>'role','')='service_role' then return new; end if;
  if tg_op='UPDATE' then
    previous:=to_jsonb(old);
    -- Auth deletes clear contributor FKs without a request JWT. Permit only
    -- those null assignments after the referenced account has been removed.
    if auth.uid() is null and r is distinct from previous
      and (r-array['contributor_id','last_editor_id']) =
          (previous-array['contributor_id','last_editor_id'])
      and not exists (
        select 1 from unnest(array['contributor_id','last_editor_id']) field
        where r->>field is distinct from previous->>field
          and (r->>field is not null or previous->>field is null or exists (
            select 1 from auth.users where id=(previous->>field)::uuid
          ))
      ) then return new; end if;
    foreach key in array array['family_id','vault_id','legacy_member_id','memory_id','legacy_memory_id'] loop
      if r->>key is distinct from previous->>key then
        raise exception 'MEDIA_PARENT_IMMUTABLE' using errcode='42501';
      end if;
    end loop;
  end if;
  if tg_table_name like 'legacy_%' then
    l:=case when tg_table_name='legacy_family_members' then (r->>'id')::uuid
      else (r->>'legacy_member_id')::uuid end;
    if tg_table_name='legacy_family_members' then f:=(r->>'family_id')::uuid;
    else select family_id into f from public.legacy_family_members where id=l; end if;
    if f is null or ((r ? 'family_id') and (r->>'family_id')::uuid is distinct from f)
      or not exists(select 1 from public.family_members where family_id=f and user_id=auth.uid()) then
      raise exception 'MEDIA_FAMILY_MISMATCH' using errcode='42501';
    end if;
    m:=nullif(r->>'legacy_memory_id','')::uuid;
    if m is not null and not exists(select 1 from public.legacy_memories
      where id=m and legacy_member_id=l and family_id=f) then
      raise exception 'MEDIA_MEMORY_MISMATCH' using errcode='42501';
    end if;
  else
    v:=(r->>'vault_id')::uuid;
    if not exists(select 1 from public.vaults where id=v and owner_id=auth.uid()) then
      raise exception 'MEDIA_VAULT_MISMATCH' using errcode='42501';
    end if;
    m:=nullif(r->>'memory_id','')::uuid;
    if m is not null and not exists(select 1 from public.memories where id=m and vault_id=v) then
      raise exception 'MEDIA_MEMORY_MISMATCH' using errcode='42501';
    end if;
  end if;
  path:=coalesce(r->>'path',r->>'storage_path',r->>'avatar_path');
  if nullif(path,'') is null then return new; end if;
  buckets:=case tg_table_name
    when 'legacy_family_members' then array['avatars','vault_photos','legacy_avatars']
    when 'legacy_member_photos' then array['vault_photos','legacy_vault_photos']
    when 'legacy_memory_photos' then array['vault_photos','memory_photos','legacy_memory_photos']
    when 'legacy_memory_voice_notes' then array['memory_voice','legacy_memory_voice']
    when 'legacy_vault_about_photos' then array['vault_photos','legacy_vault_photos']
    when 'legacy_vault_core_voice_note' then array['vault_voice','legacy_vault_voice','voice notes']
    when 'memory_photos' then array['memory_photos','vault_photos']
    when 'memory_voice_notes' then array['memory_voice']
    when 'vault_highlight_photos' then array['vault_photos']
    when 'vault_about_photos' then array['vault_photos']
    when 'vault_core_voice_note' then array['vault_voice','voice notes']
    when 'vault_voice_notes' then array['vault_voice','voice notes']
    when 'voice_notes' then array['vault_voice','voice notes']
    when 'vault_media' then array['vault_photos','memory_photos','vault_voice','memory_voice']
    else array[]::text[] end;
  if not exists(select 1 from unnest(buckets) b
    where public.media_object_matches_scope(b,path,f,v,l,m)) then
    raise exception 'MEDIA_OBJECT_SCOPE_MISMATCH' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_media_reference_scope() from public,anon,authenticated;
