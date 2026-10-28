-- Retire exact-memory attachment addresses without deleting their bytes.
-- Storage API performs the move; triggers commit references with its metadata.
create table content_safety.media_retirement_batches (
  id uuid primary key default gen_random_uuid(),
  report_id uuid references public.content_reports(id) on delete set null,
  target_kind text not null check (target_kind in ('memory','legacy_memory')),
  target_id uuid not null,
  hidden_at timestamptz not null,
  issue text check (issue in ('attachment_unavailable','shared_reference','attachment_limit','deletion_in_progress','object_changed','target_changed','unsupported_bucket')),
  created_at timestamptz not null default now(),
  unique(target_kind,target_id,hidden_at)
);
create table content_safety.media_retirement_files (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references content_safety.media_retirement_batches(id),
  object_id uuid not null,
  bucket_id text not null,
  source_path text not null,
  destination_path text not null,
  source_owner uuid,
  source_owner_id text,
  source_metadata jsonb,
  state text not null default 'pending' check (state in ('pending','moved','deleted')),
  finished_at timestamptz,
  unique(bucket_id,source_path),
  unique(bucket_id,destination_path)
);
create index media_retirement_batch_state on content_safety.media_retirement_files(batch_id,state);
create index media_retirement_source_path on content_safety.media_retirement_files(source_path);
create index media_retirement_destination_path on content_safety.media_retirement_files(destination_path);
create index media_retirement_report on content_safety.media_retirement_batches(report_id);
alter table content_safety.media_retirement_batches enable row level security;
alter table content_safety.media_retirement_files enable row level security;
revoke all on content_safety.media_retirement_batches,content_safety.media_retirement_files from public,anon,authenticated,service_role;

-- A short transaction lock, never held across Storage/network calls. Statement
-- triggers take it before row locks; deletion/review RPCs take it on entry.
create function content_safety.media_lifecycle_lock()
returns void language sql volatile security definer set search_path='' as $$
  select pg_advisory_xact_lock(831247,1);
$$;
create function content_safety.lock_media_statement()
returns trigger language plpgsql security definer set search_path='' as $$
begin perform content_safety.media_lifecycle_lock(); return null; end;
$$;
do $$ declare t text; begin
  foreach t in array array['vaults','memories','memory_photos','memory_voice_notes',
    'vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes',
    'family_members','legacy_family_members','legacy_memories','legacy_member_photos','legacy_memory_photos',
    'legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    execute format('create trigger safety_media_lifecycle before insert or update or delete on public.%I
      for each statement execute function content_safety.lock_media_statement()',t);
  end loop;
end $$;
create trigger safety_media_lifecycle before insert or update or delete on storage.objects
  for each statement execute function content_safety.lock_media_statement();

alter function public.claim_account_deletion(uuid,uuid) set schema content_safety;
alter function public.finalize_account_deletion_data(uuid,uuid) set schema content_safety;
create function public.claim_account_deletion(p_user_id uuid,p_lease_token uuid)
returns text language plpgsql security definer set search_path='' as $$
begin
  perform content_safety.media_lifecycle_lock();
  return content_safety.claim_account_deletion(p_user_id,p_lease_token);
end;
$$;
create function public.finalize_account_deletion_data(p_user_id uuid,p_lease_token uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform content_safety.media_lifecycle_lock();
  perform content_safety.finalize_account_deletion_data(p_user_id,p_lease_token);
end;
$$;

create function content_safety.memory_attachment_refs(p_kind text,p_target uuid)
returns table(relation text,row_id uuid,path text,buckets text[],family_id uuid,vault_id uuid,legacy_id uuid,scope_valid boolean)
language sql stable security definer set search_path='' as $$
  select 'memory_photos',p.id,p.path,array['vault_photos','memory_photos'],v.family_id,v.id,null::uuid,p.vault_id=v.id
    from public.memory_photos p join public.memories m on m.id=p.memory_id
    join public.vaults v on v.id=m.vault_id
    where p_kind='memory' and m.id=p_target
  union all select 'memory_voice_notes',p.id,p.path,array['memory_voice'],v.family_id,v.id,null::uuid,p.vault_id=v.id
    from public.memory_voice_notes p join public.memories m on m.id=p.memory_id
    join public.vaults v on v.id=m.vault_id
    where p_kind='memory' and m.id=p_target
  union all select 'legacy_memory_photos',p.id,p.path,array['vault_photos','memory_photos','legacy_memory_photos'],l.family_id,null::uuid,l.id,p.legacy_member_id=l.id and p.family_id=l.family_id
    from public.legacy_memory_photos p join public.legacy_memories m on m.id=p.legacy_memory_id
    join public.legacy_family_members l on l.id=m.legacy_member_id
    where p_kind='legacy_memory' and m.id=p_target
  union all select 'legacy_memory_voice_notes',p.id,p.path,array['memory_voice','legacy_memory_voice'],l.family_id,null::uuid,l.id,p.legacy_member_id=l.id and p.family_id=l.family_id
    from public.legacy_memory_voice_notes p join public.legacy_memories m on m.id=p.legacy_memory_id
    join public.legacy_family_members l on l.id=m.legacy_member_id
    where p_kind='legacy_memory' and m.id=p_target;
$$;

-- Conservatively refuse a path also referenced outside the approved memory.
-- The allowlist includes historical path/storage_path column variants.
create function content_safety.path_references(p_path text)
returns table(relation text,row_id uuid) language plpgsql stable security definer set search_path='' as $$
declare t text; c text;
begin
  foreach t in array array['vaults','legacy_family_members','memory_photos','memory_voice_notes',
    'vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes',
    'legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    for c in select column_name from information_schema.columns where table_schema='public' and table_name=t
      and column_name in ('path','storage_path','avatar_path') loop
      return query execute format('select %L::text,(to_jsonb(r)->>''id'')::uuid from public.%I r where %I=$1',t,t,c) using p_path;
    end loop;
  end loop;
end;
$$;

create function content_safety.retirement_deletion_busy(p_kind text,p_target uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.account_deletion_jobs j where
    (p_kind='memory' and exists(select 1 from public.memories m join public.vaults v on v.id=m.vault_id
      where m.id=p_target and v.owner_id=j.user_id))
    or (p_kind='legacy_memory' and exists(select 1 from public.legacy_memories m
      join public.family_members f on f.family_id=m.family_id where m.id=p_target and f.user_id=j.user_id))
    or exists(select 1 from public.account_deletion_files d
      join content_safety.memory_attachment_refs(p_kind,p_target) r on r.path in (d.source_path,d.target_path)
      where d.user_id=j.user_id));
$$;

create function content_safety.retirement_scope_unchanged(p_report_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.content_reports r where r.id=p_report_id and (
    (r.target_kind='memory' and (not exists(select 1 from public.memories where id=r.target_id) or exists(
      select 1 from public.memories m join public.vaults v on v.id=m.vault_id where m.id=r.target_id
        and v.owner_id=r.subject_user_id and (v.family_id=r.family_id or exists(select 1 from public.family_members f
          where f.family_id=r.family_id and f.user_id=v.owner_id)))))
    or (r.target_kind='legacy_memory' and (not exists(select 1 from public.legacy_memories where id=r.target_id) or exists(
      select 1 from public.legacy_memories m join public.legacy_family_members l on l.id=m.legacy_member_id
        where m.id=r.target_id and m.family_id=r.family_id and l.family_id=r.family_id)))
  ));
$$;

create function content_safety.retirement_bucket_supported(p_bucket text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from storage.buckets b where b.id=p_bucket and not b.public
    and coalesce(to_jsonb(b)->>'versioning_status','DISABLED')='DISABLED');
$$;

create function content_safety.prepare_media_retirement(p_report_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare r public.content_reports; b uuid; hidden timestamptz; ref record; obj storage.objects; n bigint;
begin
  perform content_safety.media_lifecycle_lock();
  select * into r from public.content_reports where id=p_report_id;
  if not found then raise exception 'SAFETY_REPORT_NOT_FOUND'; end if;
  if r.target_kind not in ('memory','legacy_memory') then return null; end if;
  select created_at into hidden from content_safety.restrictions where target_kind=r.target_kind and target_id=r.target_id;
  if hidden is null then return null; end if;
  insert into content_safety.media_retirement_batches(report_id,target_kind,target_id,hidden_at)
    values(r.id,r.target_kind,r.target_id,hidden) on conflict do nothing;
  select id into b from content_safety.media_retirement_batches
    where target_kind=r.target_kind and target_id=r.target_id and hidden_at=hidden;
  update content_safety.media_retirement_batches set issue=null where id=b;
  if not content_safety.retirement_scope_unchanged(p_report_id) then
    update content_safety.media_retirement_batches set issue='target_changed' where id=b; return b;
  end if;
  if content_safety.retirement_deletion_busy(r.target_kind,r.target_id) then
    update content_safety.media_retirement_batches set issue='deletion_in_progress' where id=b; return b;
  end if;
  update content_safety.media_retirement_files f set state='deleted',finished_at=now()
    where batch_id=b and state='pending' and not exists(select 1 from storage.objects o
      where o.id=f.object_id or (o.bucket_id=f.bucket_id and o.name in (f.source_path,f.destination_path)));
  select count(*) into n from content_safety.memory_attachment_refs(r.target_kind,r.target_id);
  if n>200 then update content_safety.media_retirement_batches set issue='attachment_limit' where id=b; return b; end if;
  for ref in select * from content_safety.memory_attachment_refs(r.target_kind,r.target_id) where path is not null loop
    if ref.scope_valid is distinct from true then
      update content_safety.media_retirement_batches set issue='attachment_unavailable' where id=b; continue;
    end if;
    if exists(select 1 from content_safety.media_retirement_files f where batch_id=b and state='moved'
      and destination_path=ref.path and bucket_id=any(ref.buckets)) then continue; end if;
    select count(*) into n from storage.objects where name=ref.path and bucket_id=any(ref.buckets);
    if n<>1 then
      update content_safety.media_retirement_batches set issue='attachment_unavailable' where id=b; continue;
    end if;
    select * into obj from storage.objects where name=ref.path and bucket_id=any(ref.buckets);
    if not content_safety.retirement_bucket_supported(obj.bucket_id) then
      update content_safety.media_retirement_batches set issue='unsupported_bucket' where id=b; continue;
    end if;
    if not public.media_object_matches_scope(obj.bucket_id,obj.name,ref.family_id,ref.vault_id,ref.legacy_id,r.target_id)
      or obj.name !~ '^[^/]+/.+/[^/]+$' then
      update content_safety.media_retirement_batches set issue='attachment_unavailable' where id=b; continue;
    end if;
    if exists(select 1 from content_safety.path_references(ref.path) all_refs where not exists(
      select 1 from content_safety.memory_attachment_refs(r.target_kind,r.target_id) allowed
      where allowed.path=ref.path and allowed.relation=all_refs.relation and allowed.row_id=all_refs.row_id)) then
      update content_safety.media_retirement_batches set issue='shared_reference' where id=b; continue;
    end if;
    insert into content_safety.media_retirement_files(batch_id,object_id,bucket_id,source_path,destination_path,source_owner,source_owner_id,source_metadata)
      values(b,obj.id,obj.bucket_id,obj.name,regexp_replace(obj.name,'[^/]+$',gen_random_uuid()::text
        ||coalesce(substring(obj.name from '(\.[A-Za-z0-9]{1,12})$'),'')),obj.owner,obj.owner_id,obj.metadata)
      on conflict(bucket_id,source_path) do nothing;
    if not exists(select 1 from content_safety.media_retirement_files f where batch_id=b and object_id=obj.id
      and bucket_id=obj.bucket_id and source_path=obj.name and state='pending'
      and source_metadata is not distinct from obj.metadata and source_owner is not distinct from obj.owner
      and source_owner_id is not distinct from obj.owner_id) then
      update content_safety.media_retirement_batches set issue='object_changed' where id=b;
    end if;
  end loop;
  return b;
end;
$$;

create function public.content_report_media_status(p_report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.content_reports; b content_safety.media_retirement_batches; h timestamptz; pending integer; done integer;
begin
  select * into r from public.content_reports where id=p_report_id;
  if not found then raise exception 'SAFETY_REPORT_NOT_FOUND'; end if;
  select created_at into h from content_safety.restrictions where target_kind=r.target_kind and target_id=r.target_id;
  if r.target_kind not in ('memory','legacy_memory') then
    return jsonb_build_object('state','not_applicable','hidden',h is not null,'pending',0,'completed',0);
  end if;
  select * into b from content_safety.media_retirement_batches where target_kind=r.target_kind and target_id=r.target_id
    and (h is null or hidden_at=h) order by created_at desc limit 1;
  select count(*) filter(where state='pending'),count(*) filter(where state<>'pending') into pending,done
    from content_safety.media_retirement_files where batch_id=b.id;
  return jsonb_build_object('state',case when h is null then 'visible' when b.id is null then 'pending'
    when b.issue is not null then 'blocked' when pending>0 then 'pending' else 'retired' end,
    'hidden',h is not null,'pending',pending,'completed',done,'issue',b.issue,
    'lastMovedAt',(select max(finished_at) from content_safety.media_retirement_files where batch_id=b.id and state='moved'));
end;
$$;

create function public.next_content_media_retirement(p_report_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b uuid; f content_safety.media_retirement_files;
begin
  b:=content_safety.prepare_media_retirement(p_report_id);
  if exists(select 1 from content_safety.media_retirement_batches where id=b and issue is not null) then return null; end if;
  select * into f from content_safety.media_retirement_files where batch_id=b and state='pending' order by id limit 1;
  if not found then return null; end if;
  return jsonb_build_object('id',f.id,'bucket',f.bucket_id,'source',f.source_path,'destination',f.destination_path);
end;
$$;

create function content_safety.approved_retirement_move(p_old storage.objects,p_new storage.objects)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(auth.jwt()->>'role','')='service_role' and p_new.id=p_old.id
    and p_new.bucket_id=p_old.bucket_id
    -- Storage re-HEADs the copied object: lastModified changes, not its content
    -- fingerprint, size, MIME type, encoding or cache directives.
    and (p_new.metadata-'lastModified') is not distinct from (p_old.metadata-'lastModified')
    and content_safety.retirement_bucket_supported(p_old.bucket_id)
    and exists(select 1 from content_safety.media_retirement_files f
      join content_safety.media_retirement_batches b on b.id=f.batch_id
      join content_safety.restrictions r on r.target_kind=b.target_kind and r.target_id=b.target_id and r.created_at=b.hidden_at
      where f.state='pending' and b.issue is null and f.object_id=p_old.id and f.bucket_id=p_old.bucket_id
        and f.source_path=p_old.name and f.destination_path=p_new.name
        and f.source_metadata is not distinct from p_old.metadata
        and f.source_owner is not distinct from p_old.owner and f.source_owner_id is not distinct from p_old.owner_id
        and content_safety.retirement_scope_unchanged(b.report_id)
        and not content_safety.retirement_deletion_busy(b.target_kind,b.target_id));
$$;
create function content_safety.guard_retirement_storage()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' and content_safety.approved_retirement_move(old,new) then
    -- Maintenance never changes the original ownership/scope binding.
    new.owner:=old.owner; new.owner_id:=old.owner_id; return new;
  end if;
  if exists(select 1 from content_safety.media_retirement_files where source_path=new.name or destination_path=new.name)
    or (tg_op='UPDATE' and exists(select 1 from content_safety.media_retirement_files
      where bucket_id=old.bucket_id and source_path=old.name)) then
    raise exception 'SAFETY_MEDIA_ADDRESS_RESERVED' using errcode='42501';
  end if;
  return new;
end;
$$;
create trigger aa_safety_retirement_storage before insert or update on storage.objects
  for each row execute function content_safety.guard_retirement_storage();

create function content_safety.commit_retirement_references()
returns trigger language plpgsql security definer set search_path='' as $$
declare f content_safety.media_retirement_files; b content_safety.media_retirement_batches; ref record;
begin
  if not content_safety.approved_retirement_move(old,new) then return null; end if;
  select * into f from content_safety.media_retirement_files where object_id=old.id and bucket_id=old.bucket_id
    and source_path=old.name and destination_path=new.name and state='pending';
  select * into b from content_safety.media_retirement_batches where id=f.batch_id;
  if exists(select 1 from content_safety.path_references(old.name) all_refs where not exists(
    select 1 from content_safety.memory_attachment_refs(b.target_kind,b.target_id) allowed
    where allowed.path=old.name and allowed.relation=all_refs.relation and allowed.row_id=all_refs.row_id)) then
    raise exception 'SAFETY_MEDIA_REFERENCE_CHANGED';
  end if;
  for ref in select * from content_safety.memory_attachment_refs(b.target_kind,b.target_id) where path=old.name loop
    execute format('update public.%I set path=$1 where id=$2 and path=$3',ref.relation) using new.name,ref.row_id,old.name;
  end loop;
  update content_safety.media_retirement_files set state='moved',finished_at=now() where id=f.id;
  return null;
end;
$$;
create trigger safety_commit_retirement after update on storage.objects
  for each row execute function content_safety.commit_retirement_references();

create function content_safety.guard_retirement_reference()
returns trigger language plpgsql security definer set search_path='' as $$
declare p text:=coalesce(to_jsonb(new)->>'path',to_jsonb(new)->>'storage_path',to_jsonb(new)->>'avatar_path');
  prior text; kind text; target uuid;
begin
  if tg_op='UPDATE' then prior:=coalesce(to_jsonb(old)->>'path',to_jsonb(old)->>'storage_path',to_jsonb(old)->>'avatar_path'); end if;
  if p is not distinct from prior then return new; end if;
  if exists(select 1 from content_safety.media_retirement_files where source_path=p) then
    raise exception 'SAFETY_MEDIA_ADDRESS_RETIRED' using errcode='42501';
  end if;
  if tg_table_name in ('memory_photos','memory_voice_notes') then kind:='memory'; target:=(to_jsonb(new)->>'memory_id')::uuid;
  elsif tg_table_name in ('legacy_memory_photos','legacy_memory_voice_notes') then kind:='legacy_memory'; target:=(to_jsonb(new)->>'legacy_memory_id')::uuid;
  end if;
  if exists(select 1 from content_safety.restrictions where target_kind=kind and target_id=target) then
    if coalesce(auth.jwt()->>'role','')='service_role' and (
      exists(select 1 from content_safety.media_retirement_files f join content_safety.media_retirement_batches b on b.id=f.batch_id
        join storage.objects o on o.id=f.object_id and o.bucket_id=f.bucket_id and o.name=f.destination_path
        where f.state='pending' and f.source_path=prior and f.destination_path=p and b.target_kind=kind and b.target_id=target)
      or exists(select 1 from public.account_deletion_files d join public.account_deletion_jobs j using(user_id)
        where d.source_path=prior and d.target_path=p and j.phase='preserving' and j.lease_until>now())) then return new; end if;
    raise exception 'SAFETY_MEMORY_HIDDEN' using errcode='42501';
  end if;
  return new;
end;
$$;
do $$ declare t text; begin
  foreach t in array array['vaults','legacy_family_members','memory_photos','memory_voice_notes',
    'vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes',
    'legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note'] loop
    execute format('create trigger safety_retired_reference before insert or update on public.%I
      for each row execute function content_safety.guard_retirement_reference()',t);
  end loop;
end $$;

-- Preserve every existing quota check; only an exact same-byte approved rename
-- skips a new-upload charge. No user or arbitrary service upload exception.
create or replace function public.everroot_assert_storage_object_capacity()
returns trigger language plpgsql security definer set search_path=public,storage,pg_temp as $$
declare v_folders text[];v_owner_id uuid;v_slot_id uuid;v_family_id uuid;v_vault_id uuid;
  v_limit bigint;v_used bigint;v_new_size bigint;v_old_size bigint:=0;v_lock_key text;
begin
  if tg_op='UPDATE' and content_safety.approved_retirement_move(old,new) then return new; end if;
  if coalesce(auth.jwt()->>'role','')<>'service_role' and auth.uid() is not null then
    perform pg_advisory_xact_lock(hashtext('delete:'||auth.uid()::text));
    if exists(select 1 from public.account_deletion_jobs where user_id=auth.uid()) then raise exception 'ACCOUNT_DELETION_IN_PROGRESS' using errcode='42501'; end if;
  end if;
  if new.bucket_id<>all(public.everroot_media_bucket_ids()) then return new; end if;
  v_new_size:=public.everroot_storage_metadata_size(new.metadata);
  if public.deletion_copy_authorized(new.bucket_id,new.name,v_new_size) then return new; end if;
  v_folders:=storage.foldername(new.name);
  v_owner_id:=public.everroot_try_uuid(v_folders[1]);v_slot_id:=public.everroot_try_uuid(v_folders[2]);
  if v_owner_id is null or v_slot_id is null then perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_PATH','This media upload path is not valid for EverRoot storage.'); end if;
  select id,family_id into v_vault_id,v_family_id from public.vaults where id=v_slot_id and owner_id=v_owner_id limit 1;
  if v_vault_id is null then select id into v_family_id from public.family_groups where id=v_slot_id limit 1; end if;
  if v_vault_id is null and v_family_id is null then perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_PATH','This media upload path is not linked to an EverRoot vault or family.'); end if;
  v_lock_key:=coalesce(v_family_id::text,v_vault_id::text)||':storage';
  perform pg_advisory_xact_lock(hashtext(v_lock_key));
  perform public.everroot_assert_family_writable(v_family_id);
  v_limit:=public.everroot_limit_bigint(v_family_id,'storage_bytes');
  v_used:=public.everroot_storage_bytes_used(v_family_id,v_vault_id);
  if tg_op='UPDATE' and old.bucket_id=new.bucket_id and old.name=new.name then v_old_size:=public.everroot_storage_metadata_size(old.metadata); end if;
  if greatest(v_used-v_old_size,0)+v_new_size>v_limit then perform public.everroot_quota_error('ERR_EVERROOT_STORAGE_LIMIT','This family has reached its storage allowance.'); end if;
  return new;
end;
$$;

alter function public.review_content_report(uuid,text,text,text) set schema content_safety;
create function public.review_content_report(p_report_id uuid,p_action text,p_reviewer text,p_notes text)
returns void language plpgsql security definer set search_path='' as $$
declare b uuid; s jsonb;
begin
  perform content_safety.media_lifecycle_lock();
  if p_action='restore' then
    b:=content_safety.prepare_media_retirement(p_report_id);
    s:=public.content_report_media_status(p_report_id);
    if s->>'state' in ('pending','blocked') then raise exception 'SAFETY_MEDIA_RETIREMENT_PENDING'; end if;
  end if;
  perform content_safety.review_content_report(p_report_id,p_action,p_reviewer,p_notes);
  if p_action='hide' then perform content_safety.prepare_media_retirement(p_report_id); end if;
end;
$$;
create or replace function public.review_content_report_checked(p_report_id uuid,p_action text,p_reviewer text,p_notes text,p_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare snapshot jsonb;
begin
  perform content_safety.media_lifecycle_lock();
  perform 1 from public.content_reports where id=p_report_id for update;
  snapshot:=content_safety.case_snapshot(p_report_id);
  if p_revision is distinct from snapshot->>'revision' then raise exception 'SAFETY_CASE_CHANGED'; end if;
  if not exists(select 1 from content_safety.preview_access where report_id=p_report_id and reviewer=btrim(p_reviewer)
    and revision=p_revision and purpose='content' and created_at>now()-interval '30 minutes') then raise exception 'SAFETY_PREVIEW_REQUIRED'; end if;
  perform public.review_content_report(p_report_id,p_action,p_reviewer,p_notes);
  return jsonb_build_object('id',p_report_id,'action',p_action,'status',(select status from public.content_reports where id=p_report_id));
end;
$$;

create function public.content_review_queue()
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(row_to_json(q)),'[]'::jsonb) from (
    select r.id,r.created_at,r.reason,r.status,r.target_kind,
      public.content_report_media_status(r.id)->>'state' as media_state
    from public.content_reports r where r.status in ('open','reviewing') or exists(
      select 1 from content_safety.restrictions h where h.report_id=r.id and h.target_kind in ('memory','legacy_memory')
        and public.content_report_media_status(r.id)->>'state' in ('pending','blocked'))
    order by (public.content_report_media_status(r.id)->>'state' in ('pending','blocked')) desc,r.created_at limit 50
  ) q;
$$;

revoke all on function content_safety.media_lifecycle_lock(),content_safety.lock_media_statement(),
  content_safety.claim_account_deletion(uuid,uuid),content_safety.finalize_account_deletion_data(uuid,uuid),
  content_safety.memory_attachment_refs(text,uuid),content_safety.path_references(text),
  content_safety.retirement_scope_unchanged(uuid),
  content_safety.retirement_bucket_supported(text),
  content_safety.retirement_deletion_busy(text,uuid),content_safety.prepare_media_retirement(uuid),
  content_safety.approved_retirement_move(storage.objects,storage.objects),content_safety.guard_retirement_storage(),
  content_safety.commit_retirement_references(),content_safety.guard_retirement_reference(),
  content_safety.review_content_report(uuid,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.claim_account_deletion(uuid,uuid),public.finalize_account_deletion_data(uuid,uuid),
  public.review_content_report(uuid,text,text,text),public.next_content_media_retirement(uuid),
  public.content_report_media_status(uuid),public.content_review_queue() from public,anon,authenticated;
grant execute on function public.claim_account_deletion(uuid,uuid),public.finalize_account_deletion_data(uuid,uuid),
  public.review_content_report(uuid,text,text,text),public.next_content_media_retirement(uuid),
  public.content_report_media_status(uuid),public.content_review_queue() to service_role;
