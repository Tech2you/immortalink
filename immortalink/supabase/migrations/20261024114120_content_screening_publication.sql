-- Staged only. Processing and publication enforcement are separate, default-off
-- controls. This never scans archives or dispatches provider requests.
alter table content_safety.screening_controls
  add column enforce_publication boolean not null default false,
  add constraint screening_capture_required check(not enforce_publication or eligible_after is not null);
alter table content_safety.screening_origins
  add column cleared_generation uuid,
  add column cleared_at timestamptz;

-- Remember enrolled media even after its last reference is removed. Otherwise
-- the old folder-based Storage policy could make an orphan readable again.
create table content_safety.screening_objects (
  bucket_id text not null,
  path text not null,
  object_id uuid references storage.objects(id) on delete set null,
  primary key(bucket_id,path)
);
create index screening_objects_object_idx on content_safety.screening_objects(object_id);
alter table content_safety.screening_objects enable row level security;
revoke all on content_safety.screening_objects from public,anon,authenticated,service_role;
insert into content_safety.screening_objects
  select distinct s.bucket_id,s.name,s.id from content_safety.screening_origins o
    cross join lateral content_safety.memory_attachment_refs(
      case when o.memory_id is null then 'legacy_memory' else 'memory' end,
      coalesce(o.memory_id,o.legacy_memory_id)) r
    join storage.objects s on s.name=r.path and s.bucket_id=any(r.buckets);

create function content_safety.screening_readable(p_kind text,p_target uuid,p_scope uuid,p_authors uuid[])
returns boolean language plpgsql stable security definer set search_path='' as $$
declare o content_safety.screening_origins; u uuid:=auth.uid();
begin
  if not exists(select 1 from content_safety.screening_controls where enforce_publication) then return true; end if;
  select * into o from content_safety.screening_origins where
    (p_kind='memory' and memory_id=p_target) or (p_kind='legacy_memory' and legacy_memory_id=p_target);
  if not found then return true; end if; -- Existing archives are not enrolled.
  if o.scope_id is distinct from p_scope then return false; end if;
  -- Authors can save and inspect pending work. This is only a restrictive
  -- ceiling: existing ownership, family, suspension and block rules still apply.
  return coalesce(u=any(p_authors),false) or coalesce(o.cleared_generation=o.id,false);
end;
$$;
revoke all on function content_safety.screening_readable(text,uuid,uuid,uuid[]) from public,anon,authenticated,service_role;
grant execute on function content_safety.screening_readable(text,uuid,uuid,uuid[]) to authenticated;

create function content_safety.screening_personal_readable(p_id uuid,p_vault uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select content_safety.screening_readable('memory',p_id,p_vault,
    array[(select owner_id from public.vaults where id=p_vault)]);
$$;
revoke all on function content_safety.screening_personal_readable(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function content_safety.screening_personal_readable(uuid,uuid) to authenticated;

-- Use candidate columns for parent rows: re-reading them from a STABLE helper
-- breaks INSERT ... RETURNING before the inserted row is visible to that helper.
create policy screening_read on public.memories as restrictive for select to authenticated
  using(content_safety.screening_personal_readable(id,vault_id));
create policy screening_read on public.legacy_memories as restrictive for select to authenticated
  using(content_safety.screening_readable('legacy_memory',id,legacy_member_id,array[contributor_id,last_editor_id]));

create or replace function content_safety.memory_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.memories m join public.vaults v on v.id=m.vault_id
    where m.id=p_id and content_safety.vault_visible(v.id)
      and content_safety.visible('memory',m.id,v.owner_id)
      and content_safety.screening_personal_readable(m.id,m.vault_id));
$$;
create or replace function content_safety.legacy_memory_visible(p_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.legacy_memories m where m.id=p_id
    and content_safety.legacy_visible(m.legacy_member_id)
    and content_safety.visible('legacy_memory',m.id,m.contributor_id)
    and content_safety.visible('legacy_memory',m.id,m.last_editor_id)
    and content_safety.screening_readable('legacy_memory',m.id,m.legacy_member_id,array[m.contributor_id,m.last_editor_id]));
$$;

create function content_safety.screening_object_readable(p_bucket text,p_path text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare r record; linked boolean:=false; tracked boolean;
begin
  if not exists(select 1 from content_safety.screening_controls where enforce_publication) then return true; end if;
  select exists(select 1 from content_safety.screening_objects
    where bucket_id=p_bucket and path=p_path) into tracked;
  for r in
    select p.memory_id id,'memory'::text kind from public.memory_photos p
      where p.path=p_path and p_bucket in ('vault_photos','memory_photos')
    union select p.memory_id,'memory' from public.memory_voice_notes p where p.path=p_path and p_bucket='memory_voice'
    union select p.legacy_memory_id,'legacy_memory' from public.legacy_memory_photos p
      where p.path=p_path and p_bucket in ('vault_photos','memory_photos','legacy_memory_photos')
    union select p.legacy_memory_id,'legacy_memory' from public.legacy_memory_voice_notes p
      where p.path=p_path and p_bucket in ('memory_voice','legacy_memory_voice')
  loop
    -- A new upload cannot acquire approval by being relinked to an exempt
    -- archive. Existing archive objects are not tracked by this new-upload gate.
    linked:=linked or exists(select 1 from content_safety.screening_origins
      where (r.kind='memory' and memory_id=r.id) or (r.kind='legacy_memory' and legacy_memory_id=r.id));
    if r.kind='memory' and not content_safety.memory_visible(r.id) then return false; end if;
    if r.kind='legacy_memory' and not content_safety.legacy_memory_visible(r.id) then return false; end if;
  end loop;
  if not tracked or linked then return true; end if;
  -- Upload-before-reference and removed-reference paths remain uploader-only.
  return exists(select 1 from storage.objects o where o.bucket_id=p_bucket and o.name=p_path
    and (o.owner=auth.uid() or o.owner_id=auth.uid()::text));
end;
$$;
revoke all on function content_safety.screening_object_readable(text,text) from public,anon,authenticated,service_role;
grant execute on function content_safety.screening_object_readable(text,text) to authenticated;
create policy screening_read on storage.objects as restrictive for select to authenticated
  using(content_safety.screening_object_readable(bucket_id,name));

-- A previously signed URL must never point at replacement, unscreened bytes.
-- Normal composers already upload to fresh names with upsert:false. The UPDATE
-- policy rejects client overwrite/move preflights; the tombstone rejects reuse
-- even after DELETE. Exact service-only maintenance still uses its own guards.
create function content_safety.screening_object_mutable(p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select not exists(select 1 from content_safety.screening_controls where enforce_publication)
    or not exists(select 1 from content_safety.screening_objects where bucket_id=p_bucket and path=p_path);
$$;
revoke all on function content_safety.screening_object_mutable(text,text) from public,anon,authenticated,service_role;
grant execute on function content_safety.screening_object_mutable(text,text) to authenticated;
create policy screening_immutable_address on storage.objects as restrictive for update to authenticated
  using(content_safety.screening_object_mutable(bucket_id,name))
  with check(content_safety.screening_object_mutable(bucket_id,name));
create function content_safety.guard_screening_address()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not content_safety.screening_object_mutable(new.bucket_id,new.name) then
    raise exception 'SCREENING_MEDIA_ADDRESS_USED' using errcode='42501'; end if;
  return new;
end;
$$;
revoke all on function content_safety.guard_screening_address() from public,anon,authenticated,service_role;
create trigger screening_fresh_address before insert on storage.objects
  for each row execute function content_safety.guard_screening_address();

-- Rotate the source generation, which is already included in the worker's
-- checked snapshot. Returning to old text cannot revive an earlier approval.
create function content_safety.invalidate_screening(p_kind text,p_target uuid)
returns void language sql volatile security definer set search_path='' as $$
  update content_safety.screening_origins set id=gen_random_uuid(),cleared_generation=null,cleared_at=null
    where (p_kind='memory' and memory_id=p_target) or (p_kind='legacy_memory' and legacy_memory_id=p_target);
$$;
revoke all on function content_safety.invalidate_screening(text,uuid) from public,anon,authenticated,service_role;

create function content_safety.screening_source_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb; after_row jsonb; kind text; previous_id uuid; next_id uuid; p text; prior text;
  pure_attribution_cleanup boolean:=false; maintenance boolean:=false;
begin
  perform content_safety.media_lifecycle_lock();
  if tg_op<>'INSERT' then before_row:=to_jsonb(old); end if;
  if tg_op<>'DELETE' then after_row:=to_jsonb(new); end if;
  kind:=case when tg_table_name like 'legacy_%' then 'legacy_memory' else 'memory' end;
  if tg_table_name in ('memories','legacy_memories') then
    previous_id:=(before_row->>'id')::uuid; next_id:=(after_row->>'id')::uuid;
  else
    previous_id:=coalesce(before_row->>'memory_id',before_row->>'legacy_memory_id')::uuid;
    next_id:=coalesce(after_row->>'memory_id',after_row->>'legacy_memory_id')::uuid;
  end if;
  if tg_op='UPDATE' then
    if before_row=after_row then return null; end if;
    -- FK nulling after account removal is not a content edit and must not hide
    -- approved shared legacy contributions. A live author reassignment is.
    pure_attribution_cleanup:=
      (before_row-array['contributor_id','last_editor_id'])=(after_row-array['contributor_id','last_editor_id'])
      and not exists(select 1 from unnest(array['contributor_id','last_editor_id']) key
        where before_row->>key is distinct from after_row->>key
          and (after_row->>key is not null or exists(select 1 from auth.users where id=(before_row->>key)::uuid)));
    if pure_attribution_cleanup then return null; end if;
    prior:=before_row->>'path'; p:=after_row->>'path';
    if prior is distinct from p and (before_row-'path')=(after_row-'path')
      and coalesce(auth.jwt()->>'role','')='service_role' then
      -- Existing exact same-byte retirement and deletion manifests are the only
      -- path-only maintenance exceptions. Arbitrary service writes invalidate.
      maintenance:=exists(select 1 from content_safety.media_retirement_files f
        join content_safety.media_retirement_batches b on b.id=f.batch_id
        join storage.objects o on o.id=f.object_id and o.name=f.destination_path and o.bucket_id=f.bucket_id
        where f.state='pending' and f.source_path=prior and f.destination_path=p
          and b.target_kind=kind and b.target_id=next_id)
        or exists(select 1 from public.account_deletion_files f join public.account_deletion_jobs j using(user_id)
          join storage.objects src on src.bucket_id=f.bucket_id and src.name=f.source_path
          join storage.objects dst on dst.bucket_id=f.bucket_id and dst.name=f.target_path
          where j.phase='preserving' and j.lease_until>now() and f.source_path=prior and f.target_path=p
            and src.metadata->>'eTag' is not null
            and (src.metadata-'lastModified')=(dst.metadata-'lastModified')
            and dst.owner is null and coalesce(dst.owner_id,'')='');
    end if;
  end if;
  if not maintenance then
    if previous_id is not null then perform content_safety.invalidate_screening(kind,previous_id); end if;
    if next_id is not null and next_id is distinct from previous_id then perform content_safety.invalidate_screening(kind,next_id); end if;
  end if;
  if tg_table_name not in ('memories','legacy_memories') and next_id is not null
    and exists(select 1 from content_safety.screening_origins where memory_id=next_id or legacy_memory_id=next_id) then
    insert into content_safety.screening_objects select o.bucket_id,o.name,o.id from storage.objects o
      where o.name=after_row->>'path' and o.bucket_id in ('vault_photos','memory_photos','memory_voice','legacy_memory_photos','legacy_memory_voice')
      on conflict do nothing;
  end if;
  return null;
end;
$$;
revoke all on function content_safety.screening_source_changed() from public,anon,authenticated,service_role;
create trigger screening_source_changed after update on public.memories
  for each row execute function content_safety.screening_source_changed();
create trigger screening_source_changed after update on public.legacy_memories
  for each row execute function content_safety.screening_source_changed();
do $$ declare t text; begin
  foreach t in array array['memory_photos','memory_voice_notes','legacy_memory_photos','legacy_memory_voice_notes'] loop
    execute format('create trigger screening_source_changed after insert or update or delete on public.%I
      for each row execute function content_safety.screening_source_changed()',t);
  end loop;
end $$;

create function content_safety.screening_storage_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record; paths text[]; buckets text[]; approved_move boolean:=false;
begin
  perform content_safety.media_lifecycle_lock();
  if tg_op='UPDATE' then
    approved_move:=content_safety.approved_retirement_move(old,new);
    if old.bucket_id=new.bucket_id and old.name=new.name and old.metadata=new.metadata then return null; end if;
  end if;
  if tg_op<>'DELETE' and exists(select 1 from content_safety.screening_controls
    where eligible_after is not null and eligible_after<=clock_timestamp())
    and new.bucket_id in ('vault_photos','memory_photos','memory_voice','legacy_memory_photos','legacy_memory_voice')
    and (split_part(new.name,'/',3)='memories' or split_part(new.name,'/',5)='memories') then
    insert into content_safety.screening_objects values(new.bucket_id,new.name,new.id) on conflict do nothing;
  end if;
  if approved_move then return null; end if;
  if tg_op='INSERT' then paths:=array[new.name]; buckets:=array[new.bucket_id];
  elsif tg_op='DELETE' then paths:=array[old.name]; buckets:=array[old.bucket_id];
  else paths:=array[old.name,new.name]; buckets:=array[old.bucket_id,new.bucket_id]; end if;
  for r in
    select 'memory'::text kind,p.memory_id id from public.memory_photos p where p.path=any(paths)
      and buckets && array['vault_photos','memory_photos']
    union select 'memory',p.memory_id from public.memory_voice_notes p where p.path=any(paths) and 'memory_voice'=any(buckets)
    union select 'legacy_memory',p.legacy_memory_id from public.legacy_memory_photos p where p.path=any(paths)
      and buckets && array['vault_photos','memory_photos','legacy_memory_photos']
    union select 'legacy_memory',p.legacy_memory_id from public.legacy_memory_voice_notes p where p.path=any(paths)
      and buckets && array['memory_voice','legacy_memory_voice']
  loop perform content_safety.invalidate_screening(r.kind,r.id); end loop;
  return null;
end;
$$;
revoke all on function content_safety.screening_storage_changed() from public,anon,authenticated,service_role;
-- Run before safety_commit_retirement consumes its pending manifest.
create trigger ab_screening_storage_changed after insert or update or delete on storage.objects
  for each row execute function content_safety.screening_storage_changed();

create function content_safety.screening_parent_changed()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='vaults' and new.family_id is not distinct from old.family_id
    and to_jsonb(new)->>'owner_id' is not distinct from to_jsonb(old)->>'owner_id' then return null; end if;
  if tg_table_name='legacy_family_members' and new.family_id is not distinct from old.family_id then return null; end if;
  perform content_safety.media_lifecycle_lock();
  update content_safety.screening_origins set id=gen_random_uuid(),cleared_generation=null,cleared_at=null where scope_id=old.id;
  return null;
end;
$$;
revoke all on function content_safety.screening_parent_changed() from public,anon,authenticated,service_role;
create trigger screening_parent_changed after update on public.vaults
  for each row execute function content_safety.screening_parent_changed();
create trigger screening_parent_changed after update on public.legacy_family_members
  for each row execute function content_safety.screening_parent_changed();

-- Approval is durable for this exact content generation, not for a user's
-- ongoing permission or subscription. The worker still rechecks permission,
-- source, lease, scope and restrictions before accepting its result.
create or replace function public.finish_content_screening(p_job uuid,p_lease uuid,p_outcome text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j content_safety.screening_jobs; s jsonb; next_state text; next_code text;
begin
  if p_outcome is null or p_outcome not in ('clear','review','pending') then
    raise exception 'Invalid screening outcome' using errcode='22023'; end if;
  perform content_safety.media_lifecycle_lock();
  perform 1 from content_safety.screening_controls where singleton for update;
  select * into j from content_safety.screening_jobs where id=p_job for update;
  if not found or j.state<>'leased' or j.lease_token is distinct from p_lease
    or j.lease_until<=clock_timestamp() or not j.dispatched then
    return jsonb_build_object('code','LEASE_UNAVAILABLE'); end if;
  s:=content_safety.screening_snapshot(j.target_kind,j.target_id,j.actor_id);
  if s->>'code'<>'READY' or s->>'revision' is distinct from j.revision then
    next_state:='stale'; next_code:='SOURCE_CHANGED';
  elsif p_outcome='pending' then
    next_state:=case when j.attempts<3 then 'queued' else 'review' end;
    next_code:=case when j.attempts<3 then 'PROVIDER_UNAVAILABLE' else 'RETRY_LIMIT' end;
  else
    next_state:=p_outcome;
    next_code:=case when p_outcome='clear' then 'REVISION_CLEAR' else 'HUMAN_REVIEW_REQUIRED' end;
  end if;
  update content_safety.screening_jobs set state=next_state,code=next_code,
    lease_token=null,lease_until=null,dispatched=false,
    available_at=clock_timestamp()+case when j.attempts=1 then interval '1 minute' else interval '5 minutes' end,
    updated_at=clock_timestamp() where id=j.id;
  if next_state='clear' then
    update content_safety.screening_origins set cleared_generation=id,cleared_at=clock_timestamp()
      where (j.target_kind='memory' and memory_id=j.target_id)
        or (j.target_kind='legacy_memory' and legacy_memory_id=j.target_id);
  end if;
  return jsonb_build_object('state',next_state,'code',next_code);
end;
$$;
