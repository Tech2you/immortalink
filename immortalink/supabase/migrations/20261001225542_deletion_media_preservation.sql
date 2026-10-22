-- Private, durable work records. Storage bytes are changed only through its API.
create table public.account_deletion_jobs (
  user_id uuid primary key,
  phase text not null default 'preserving' check(phase in ('preserving','cleanup')),
  lease_token uuid not null,
  lease_until timestamptz not null,
  created_at timestamptz not null default now()
);
create table public.account_deletion_files (
  user_id uuid not null references public.account_deletion_jobs(user_id) on delete cascade,
  bucket_id text not null,
  source_path text not null,
  target_path text,
  keep_source boolean not null default false,
  family_id uuid,
  size_bytes bigint not null,
  primary key(user_id,bucket_id,source_path),
  unique(bucket_id,target_path)
);
alter table public.account_deletion_jobs enable row level security;
alter table public.account_deletion_files enable row level security;
revoke all on public.account_deletion_jobs,public.account_deletion_files from public,anon,authenticated;
grant all on public.account_deletion_jobs,public.account_deletion_files to service_role;

create view public.legacy_media_references as
  select 'legacy_family_members'::text relation_name,id row_id,family_id,avatar_path path,
    array['avatars','vault_photos','legacy_avatars']::text[] buckets
    from public.legacy_family_members where nullif(avatar_path,'') is not null
  union all select 'legacy_member_photos',p.id,l.family_id,p.path,array['vault_photos','legacy_vault_photos']
    from public.legacy_member_photos p join public.legacy_family_members l on l.id=p.legacy_member_id
  union all select 'legacy_memory_photos',p.id,l.family_id,p.path,array['vault_photos','memory_photos','legacy_memory_photos']
    from public.legacy_memory_photos p join public.legacy_family_members l on l.id=p.legacy_member_id
  union all select 'legacy_memory_voice_notes',p.id,l.family_id,p.path,array['memory_voice','legacy_memory_voice']
    from public.legacy_memory_voice_notes p join public.legacy_family_members l on l.id=p.legacy_member_id
  union all select 'legacy_vault_about_photos',p.id,l.family_id,p.path,array['vault_photos','legacy_vault_photos']
    from public.legacy_vault_about_photos p join public.legacy_family_members l on l.id=p.legacy_member_id
  union all select 'legacy_vault_core_voice_note',p.id,l.family_id,p.path,array['vault_voice','legacy_vault_voice','voice notes']
    from public.legacy_vault_core_voice_note p join public.legacy_family_members l on l.id=p.legacy_member_id;
revoke all on public.legacy_media_references from public,anon,authenticated;
grant select on public.legacy_media_references to service_role;

create function public.claim_account_deletion(p_user_id uuid,p_lease_token uuid)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_job public.account_deletion_jobs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext('delete:'||p_user_id::text));
  select * into v_job from public.account_deletion_jobs where user_id=p_user_id for update;
  if found then
    if v_job.lease_until>now() then raise exception 'ACCOUNT_DELETION_BUSY'; end if;
    update public.account_deletion_jobs set lease_token=p_lease_token,lease_until=now()+interval '2 minutes'
      where user_id=p_user_id;
    return v_job.phase;
  end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'ACCOUNT_NOT_FOUND'; end if;
  insert into public.account_deletion_jobs(user_id,lease_token,lease_until)
    values(p_user_id,p_lease_token,now()+interval '2 minutes');
  -- Concurrent app writes acquire the same account lock in the guard below.
  if exists(select 1 from public.legacy_media_references r
    join storage.objects o on o.name=r.path and o.bucket_id=any(r.buckets)
    where o.owner_id=p_user_id::text or o.owner=p_user_id or split_part(o.name,'/',1)=p_user_id::text
    group by o.bucket_id,o.name having count(distinct r.family_id)>1) then
    raise exception 'SHARED_MEDIA_MULTIPLE_FAMILIES';
  end if;
  insert into public.account_deletion_files(user_id,bucket_id,source_path,target_path,family_id,size_bytes,keep_source)
  select p_user_id,o.bucket_id,o.name,
    case when r.family_id is not null then gen_random_uuid()::text||'/'||r.family_id::text||'/retained/'||o.id::text end,
    r.family_id,coalesce((o.metadata->>'size')::bigint,0),o.bucket_id='family_avatars' and r.family_id is not null
  from storage.objects o
  left join lateral (select family_id from public.legacy_media_references
    where path=o.name and o.bucket_id=any(buckets)
    union select fg.id from public.family_groups fg where o.bucket_id='family_avatars'
      and o.name=fg.id::text||'/avatar' and exists(select 1 from public.family_members
        where family_id=fg.id and user_id<>p_user_id)
    order by family_id limit 1) r on true
  where o.owner_id=p_user_id::text or o.owner=p_user_id or split_part(o.name,'/',1)=p_user_id::text;
  return 'preserving';
end;
$$;

-- Prevent writes racing the snapshot. Other family members remain able to edit
-- the tree, but cannot attach a path being removed by an account deletion.
create function public.guard_account_deletion_write()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_path text;
begin
  if coalesce(auth.jwt()->>'role','')='service_role' then return new; end if;
  if v_user is not null then
    perform pg_advisory_xact_lock(hashtext('delete:'||v_user::text));
    if exists(select 1 from public.account_deletion_jobs where user_id=v_user) then
      raise exception 'ACCOUNT_DELETION_IN_PROGRESS' using errcode='42501';
    end if;
  end if;
  v_path:=coalesce(to_jsonb(new)->>'path',to_jsonb(new)->>'avatar_path');
  if tg_op='UPDATE' and v_path is not distinct from coalesce(to_jsonb(old)->>'path',to_jsonb(old)->>'avatar_path') then
    return new;
  end if;
  if v_path is not null and (exists(select 1 from public.account_deletion_jobs
    where user_id::text=split_part(v_path,'/',1)) or exists(
      select 1 from public.account_deletion_files where source_path=v_path)) then
    raise exception 'MEDIA_ACCOUNT_DELETION_IN_PROGRESS' using errcode='42501';
  end if;
  return new;
end;
$$;
do $$ declare t text; begin
  foreach t in array array['vaults','memories','memory_photos','memory_voice_notes',
    'vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes',
    'family_members','legacy_family_members','legacy_member_photos','legacy_memory_photos',
    'legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    execute format('create trigger account_deletion_write_guard before insert or update on public.%I
      for each row execute function public.guard_account_deletion_write()',t);
  end loop;
end $$;

create function public.deletion_copy_authorized(p_bucket text,p_path text,p_size bigint)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(auth.jwt()->>'role','')='service_role' and exists(
    select 1 from public.account_deletion_files f join public.account_deletion_jobs j using(user_id)
    where f.bucket_id=p_bucket and f.target_path=p_path and j.phase='preserving'
      and j.lease_until>now() and p_size<=f.size_bytes
  );
$$;

create function public.guard_deletion_storage_write()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row jsonb;
begin
  if tg_op='DELETE' then v_row:=to_jsonb(old); else v_row:=to_jsonb(new); end if;
  if coalesce(auth.jwt()->>'role','')<>'service_role' and exists(
    select 1 from public.account_deletion_files f join public.account_deletion_jobs j using(user_id)
    where j.phase='preserving' and f.bucket_id=v_row->>'bucket_id'
      and (f.source_path=v_row->>'name' or f.target_path=v_row->>'name')
  ) then raise exception 'MEDIA_ACCOUNT_DELETION_IN_PROGRESS' using errcode='42501'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
create trigger account_deletion_storage_guard before insert or update or delete on storage.objects
  for each row execute function public.guard_deletion_storage_write();

-- The only quota exception is a service-role copy named in the private manifest.
-- It preserves existing bytes, and is not a new user upload or extra allowance.
create or replace function public.everroot_assert_storage_object_capacity()
returns trigger language plpgsql security definer set search_path=public,storage,pg_temp as $$
declare v_folders text[];v_owner_id uuid;v_slot_id uuid;v_family_id uuid;v_vault_id uuid;
  v_limit bigint;v_used bigint;v_new_size bigint;v_old_size bigint:=0;v_lock_key text;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' and auth.uid() is not null then
    perform pg_advisory_xact_lock(hashtext('delete:'||auth.uid()::text));
    if exists(select 1 from public.account_deletion_jobs where user_id=auth.uid()) then
      raise exception 'ACCOUNT_DELETION_IN_PROGRESS' using errcode='42501';
    end if;
  end if;
  if new.bucket_id<>all(public.everroot_media_bucket_ids()) then return new; end if;
  v_new_size:=public.everroot_storage_metadata_size(new.metadata);
  if public.deletion_copy_authorized(new.bucket_id,new.name,v_new_size) then return new; end if;
  v_folders:=storage.foldername(new.name);
  v_owner_id:=public.everroot_try_uuid(v_folders[1]);v_slot_id:=public.everroot_try_uuid(v_folders[2]);
  if v_owner_id is null or v_slot_id is null then
    perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_PATH','This media upload path is not valid for EverRoot storage.');
  end if;
  select id,family_id into v_vault_id,v_family_id from public.vaults
    where id=v_slot_id and owner_id=v_owner_id limit 1;
  if v_vault_id is null then select id into v_family_id from public.family_groups where id=v_slot_id limit 1; end if;
  if v_vault_id is null and v_family_id is null then
    perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_PATH','This media upload path is not linked to an EverRoot vault or family.');
  end if;
  v_lock_key:=coalesce(v_family_id::text,v_vault_id::text)||':storage';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));
  perform public.everroot_assert_family_writable(v_family_id);
  v_limit:=public.everroot_limit_bigint(v_family_id,'storage_bytes');
  v_used:=public.everroot_storage_bytes_used(v_family_id,v_vault_id);
  if tg_op='UPDATE' and old.bucket_id=new.bucket_id and old.name=new.name then
    v_old_size:=public.everroot_storage_metadata_size(old.metadata);
  end if;
  if greatest(v_used-v_old_size,0)+v_new_size>v_limit then
    perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_LIMIT','This family has reached its storage allowance.');
  end if;
  return new;
end;
$$;

create or replace function public.everroot_assert_legacy_avatar_storage_capacity()
returns trigger language plpgsql security definer set search_path=public,storage,pg_temp as $$
begin
  if tg_op='UPDATE' and coalesce(new.avatar_path,'')=coalesce(old.avatar_path,'') then return new; end if;
  if tg_op='UPDATE' and coalesce(auth.jwt()->>'role','')='service_role' and exists(
    select 1 from public.account_deletion_files f join storage.objects o on o.bucket_id=f.bucket_id and o.name=f.target_path
    where f.source_path=old.avatar_path and f.target_path=new.avatar_path and f.family_id=new.family_id
      and coalesce((o.metadata->>'size')::bigint,0)=f.size_bytes and coalesce(o.owner_id,'')='' and o.owner is null
  ) then return new; end if;
  perform public.everroot_assert_storage_capacity(new.family_id,null,new.avatar_path);
  return new;
end;
$$;

create function public.finalize_account_deletion_data(p_user_id uuid,p_lease_token uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.account_deletion_jobs%rowtype;v_file record;v_ref record;v_family uuid;v_vaults uuid[];v_memories uuid[];t text;
begin
  perform pg_advisory_xact_lock(hashtext('delete:'||p_user_id::text));
  select * into j from public.account_deletion_jobs where user_id=p_user_id for update;
  if not found or j.lease_token<>p_lease_token or j.lease_until<=now() then raise exception 'ACCOUNT_DELETION_LEASE_LOST'; end if;
  if j.phase='cleanup' then return; end if;
  -- Block new shared references only during this short, atomic switch.
  lock table public.legacy_family_members,public.legacy_member_photos,public.legacy_memory_photos,
    public.legacy_memory_voice_notes,public.legacy_vault_about_photos,public.legacy_vault_core_voice_note
    in share row exclusive mode;
  for v_file in select * from public.account_deletion_files where user_id=p_user_id and target_path is not null loop
    if not exists(select 1 from storage.objects where bucket_id=v_file.bucket_id and name=v_file.target_path
      and coalesce(owner_id,'')='' and owner is null and coalesce((metadata->>'size')::bigint,0)=v_file.size_bytes) then
      raise exception 'SHARED_MEDIA_COPY_REQUIRED';
    end if;
    if v_file.keep_source then
      if not exists(select 1 from storage.objects where bucket_id=v_file.bucket_id and name=v_file.source_path
        and coalesce(owner_id,'')='' and owner is null and coalesce((metadata->>'size')::bigint,0)=v_file.size_bytes) then
        raise exception 'SHARED_MEDIA_REHOME_REQUIRED';
      end if;
      continue;
    end if;
    for v_ref in select * from public.legacy_media_references where path=v_file.source_path and v_file.bucket_id=any(buckets) loop
      execute format('update public.%I set %I=$1 where id=$2',v_ref.relation_name,
        case when v_ref.relation_name='legacy_family_members' then 'avatar_path' else 'path' end)
        using v_file.target_path,v_ref.row_id;
    end loop;
  end loop;
  if exists(select 1 from public.legacy_media_references r join public.account_deletion_files f
    on f.source_path=r.path and f.bucket_id=any(r.buckets) where f.user_id=p_user_id) then
    raise exception 'SHARED_MEDIA_NOT_PRESERVED';
  end if;
  select array_agg(id) into v_vaults from public.vaults where owner_id=p_user_id;
  select array_agg(id) into v_memories from public.memories where vault_id=any(v_vaults);
  -- Lock families in a stable order; membership triggers use the same locks.
  for v_family in select family_id from public.family_members where user_id=p_user_id order by family_id loop
    perform public.handoff_family_for_account_deletion(v_family,p_user_id);
    if not exists(select 1 from public.family_members where family_id=v_family and user_id<>p_user_id) then
      update public.account_deletion_files set keep_source=false where user_id=p_user_id and family_id=v_family;
      insert into public.account_deletion_files(user_id,bucket_id,source_path,size_bytes)
      select p_user_id,o.bucket_id,o.name,coalesce((o.metadata->>'size')::bigint,0)
      from storage.objects o where (exists(select 1 from public.legacy_media_references r
        where r.family_id=v_family and r.path=o.name and o.bucket_id=any(r.buckets))
        or (o.bucket_id='family_avatars' and o.name=v_family::text||'/avatar')
        or exists(select 1 from public.account_deletion_files where user_id=p_user_id and family_id=v_family
          and bucket_id=o.bucket_id and target_path=o.name))
        and not exists(select 1 from public.legacy_media_references r where r.family_id<>v_family
          and r.path=o.name and o.bucket_id=any(r.buckets))
      on conflict do nothing;
      -- Some historical tables have no family_id; delete by legacy profile.
      delete from public.legacy_memory_chunks where legacy_member_id in
        (select id from public.legacy_family_members where family_id=v_family);
    end if;
    delete from public.family_members where family_id=v_family and user_id=p_user_id;
    if not exists(select 1 from public.family_members where family_id=v_family) then
      perform public.destroy_empty_family_group_tree(v_family);
    end if;
  end loop;
  delete from public.family_relationships where (parent_type='vault' and parent_id=any(v_vaults))
    or (child_type='vault' and child_id=any(v_vaults));
  delete from public.family_invites where created_by=p_user_id or inviter_vault_id=any(v_vaults);
  foreach t in array array['memory_voice_notes','memory_photos','memory_chunks'] loop
    execute format('delete from public.%I where memory_id=any($1)',t) using v_memories;
  end loop;
  foreach t in array array['vault_highlight_photos','vault_about_photos','vault_core_voice_note','memories','voice_notes'] loop
    execute format('delete from public.%I where vault_id=any($1)',t) using v_vaults;
  end loop;
  delete from public.family_feed_hidden_vaults where user_id=p_user_id or hidden_vault_id=any(v_vaults);
  delete from public.vaults where owner_id=p_user_id;
  update public.account_deletion_jobs set phase='cleanup' where user_id=p_user_id;
end;
$$;

create function public.account_deletion_copy_ready(p_user_id uuid,p_bucket text,p_source text,p_original boolean default false)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.account_deletion_files f join storage.objects o
    on o.bucket_id=f.bucket_id and o.name=case when p_original then f.source_path else f.target_path end
    where f.user_id=p_user_id and f.bucket_id=p_bucket and f.source_path=p_source
      and coalesce(o.owner_id,'')='' and o.owner is null and coalesce((o.metadata->>'size')::bigint,0)=f.size_bytes);
$$;
create function public.account_deletion_storage_clean(p_user_id uuid,p_lease_token uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.account_deletion_jobs where user_id=p_user_id
    and phase='cleanup' and lease_token=p_lease_token and lease_until>now())
    and not exists(select 1 from storage.objects o where o.owner_id=p_user_id::text or o.owner=p_user_id
      or split_part(o.name,'/',1)=p_user_id::text
      or exists(select 1 from public.account_deletion_files f where f.user_id=p_user_id
        and f.bucket_id=o.bucket_id and (case when f.keep_source then f.target_path else f.source_path end)=o.name));
$$;
create function public.account_deletion_session_current(p_user_id uuid,p_session_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from auth.sessions where id=p_session_id and user_id=p_user_id
    and (not_after is null or not_after>now()));
$$;

-- All surviving members can read preserved shared media by its current reference.
create or replace function public.can_read_legacy_gallery_object(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select auth.uid() is not null and exists(select 1 from public.legacy_media_references r
    join public.family_members fm on fm.family_id=r.family_id and fm.user_id=auth.uid()
    where r.path=p_name and p_bucket=any(r.buckets));
$$;
create function public.can_manage_retained_legacy_media(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select auth.uid() is not null and p_bucket=any(public.everroot_media_bucket_ids())
    and split_part(p_name,'/',3)='retained' and exists(
    select 1 from public.family_members where user_id=auth.uid() and family_id::text=split_part(p_name,'/',2));
$$;
revoke all on function public.can_manage_retained_legacy_media(text,text) from public,anon;
grant execute on function public.can_manage_retained_legacy_media(text,text) to authenticated;
create policy retained_legacy_media_read on storage.objects for select to authenticated using (
  owner is null and coalesce(owner_id,'')='' and public.can_manage_retained_legacy_media(bucket_id,name));
create policy retained_legacy_media_delete on storage.objects for delete to authenticated using (
  owner is null and coalesce(owner_id,'')='' and public.can_manage_retained_legacy_media(bucket_id,name));
revoke all on function public.claim_account_deletion(uuid,uuid),
  public.finalize_account_deletion_data(uuid,uuid),public.deletion_copy_authorized(text,text,bigint),
  public.guard_account_deletion_write(),public.guard_deletion_storage_write(),public.account_deletion_copy_ready(uuid,text,text,boolean),
  public.account_deletion_storage_clean(uuid,uuid),public.account_deletion_session_current(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.claim_account_deletion(uuid,uuid),
  public.finalize_account_deletion_data(uuid,uuid),public.account_deletion_copy_ready(uuid,text,text,boolean),
  public.account_deletion_storage_clean(uuid,uuid),public.account_deletion_session_current(uuid,uuid) to service_role;
