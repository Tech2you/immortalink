-- A readable metadata row must never confer access to an unrelated object.
create function public.media_object_matches_scope(
  p_bucket text, p_path text, p_family uuid, p_vault uuid,
  p_legacy uuid, p_memory uuid default null
) returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select exists (
    select 1 from storage.objects o where o.bucket_id=p_bucket and o.name=p_path
    and (
      (p_legacy is not null and p_family is not null
        and split_part(p_path,'/',2)=p_family::text
        and split_part(p_path,'/',3)='retained'
        and o.owner is null and coalesce(o.owner_id,'')='')
      or (
        (o.owner_id=split_part(p_path,'/',1) or o.owner::text=split_part(p_path,'/',1))
        and (
          (p_legacy is not null and p_family is not null
            and split_part(p_path,'/',2)=p_family::text
            and split_part(p_path,'/',3)='legacy'
            and split_part(p_path,'/',4)=p_legacy::text
            and (p_memory is null or (split_part(p_path,'/',5)='memories'
              and split_part(p_path,'/',6)=p_memory::text)))
          or (p_vault is not null and p_legacy is null
            and exists(select 1 from public.vaults v where v.id=p_vault
              and v.owner_id::text=split_part(p_path,'/',1)
              and v.id::text=split_part(p_path,'/',2))
            and (p_memory is null or (split_part(p_path,'/',3)='memories'
              and split_part(p_path,'/',4)=p_memory::text)))
        )
      )
    )
  );
$$;
revoke all on function public.media_object_matches_scope(text,text,uuid,uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.media_object_matches_scope(text,text,uuid,uuid,uuid,uuid) to service_role;

create function public.guard_media_reference_scope()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare
  r jsonb:=to_jsonb(new); previous jsonb; f uuid; v uuid; l uuid; m uuid;
  path text; buckets text[]; key text;
begin
  if coalesce(auth.jwt()->>'role','')='service_role' then return new; end if;
  if tg_op='UPDATE' then
    previous:=to_jsonb(old);
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
do $$ declare t text; begin
  foreach t in array array['legacy_family_members','legacy_memories','legacy_member_photos',
    'legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note',
    'memory_photos','memory_voice_notes','vault_highlight_photos','vault_about_photos',
    'vault_core_voice_note','voice_notes','vault_media','vault_voice_notes'] loop
    execute format('create trigger media_reference_scope_guard before insert or update on public.%I
      for each row execute function public.guard_media_reference_scope()',t);
  end loop;
end $$;

-- Scope checks also apply to existing rows, including any forged historical row.
create or replace function public.can_read_legacy_gallery_object(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select auth.uid() is not null and exists(
    select 1 from public.legacy_media_references r
    join public.family_members fm on fm.family_id=r.family_id and fm.user_id=auth.uid()
    join public.legacy_family_members l on l.family_id=r.family_id
    where r.path=p_name and p_bucket=any(r.buckets)
      and public.media_object_matches_scope(p_bucket,p_name,r.family_id,null,l.id)
  );
$$;
create or replace function public.can_read_shared_media_object(p_bucket_id text,p_name text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select auth.uid() is not null and p_bucket_id in ('vault_photos','memory_photos','vault_voice','memory_voice')
    and (public.can_read_legacy_gallery_object(p_bucket_id,p_name) or exists(
      select 1 from public.vaults v where v.id::text=split_part(p_name,'/',2)
        and public.media_object_matches_scope(p_bucket_id,p_name,null,v.id,null)
        and public.can_read_vault_media(v.id)
    ));
$$;
