-- New edits must not borrow the exemption of an untouched archive. No backfill.
create or replace function content_safety.invalidate_screening(p_kind text,p_target uuid)
returns void language plpgsql volatile security definer set search_path='' as $$
begin
  if not exists(select 1 from content_safety.screening_controls
    where eligible_after is not null and eligible_after<=clock_timestamp()) then return; end if;
  if p_kind='memory' then
    insert into content_safety.screening_origins(memory_id,scope_id)
      select id,vault_id from public.memories where id=p_target on conflict(memory_id) do nothing;
  elsif p_kind='legacy_memory' then
    insert into content_safety.screening_origins(legacy_memory_id,scope_id)
      select id,legacy_member_id from public.legacy_memories where id=p_target on conflict(legacy_memory_id) do nothing;
  else return; end if;
  update content_safety.screening_origins set id=gen_random_uuid(),cleared_generation=null,cleared_at=null,requested_at=null
    where (p_kind='memory' and memory_id=p_target) or (p_kind='legacy_memory' and legacy_memory_id=p_target);
  insert into content_safety.screening_objects
    select s.bucket_id,s.name,s.id from content_safety.memory_attachment_refs(p_kind,p_target) r
      join storage.objects s on s.name=r.path and s.bucket_id=any(r.buckets)
    on conflict do nothing;
end;
$$;

create or replace function content_safety.screening_source_changed()
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
    -- Timestamps alone do not change user content. Server-generated voice
    -- transcripts keep the recording's existing report/block treatment.
    if (before_row-'updated_at')=(after_row-'updated_at') then return null; end if;
    if tg_table_name in ('memory_voice_notes','legacy_memory_voice_notes')
      and coalesce(auth.jwt()->>'role','')='service_role'
      and (before_row-array['transcript','updated_at'])=(after_row-array['transcript','updated_at']) then return null; end if;
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
