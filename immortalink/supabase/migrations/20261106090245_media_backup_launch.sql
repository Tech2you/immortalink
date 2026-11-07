-- Independent media recovery. Installs OFF; no app policies, billing, media or
-- client permissions change. R2 credentials belong only in Edge secrets.
create schema media_backup;
revoke all on schema media_backup from public,anon,authenticated,service_role;

create table media_backup.control (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  max_retained_bytes bigint not null default 9000000000 check(max_retained_bytes between 1 and 1000000000000),
  max_daily_copy_bytes bigint not null default 1000000000 check(max_daily_copy_bytes between 1 and 10000000000),
  retention_days integer not null default 30 check(retention_days between 7 and 30),
  day date, copy_bytes bigint not null default 0 check(copy_bytes>=0),
  runs integer not null default 0 check(runs>=0),
  run_hash text, issued_until timestamptz, busy_until timestamptz, claimed boolean not null default false,
  last_run_at timestamptz, last_complete_at timestamptz, last_manifest_at timestamptz,
  last_error text, last_error_at timestamptz
);
insert into media_backup.control(singleton) values(true);
create table media_backup.copies (
  fingerprint text primary key check(fingerprint ~ '^[a-f0-9]{64}$'),
  object_id uuid not null, bucket text not null, object_name text not null,
  source_updated_at timestamptz not null, byte_size bigint not null check(byte_size between 0 and 52428800),
  source_etag text,
  state text not null default 'pending' check(state in ('pending','complete','deleted')),
  sha256 text, md5 text, copied_at timestamptz, retired_at timestamptz, deleted_at timestamptz,
  attempt_after timestamptz not null default now(), attempts integer not null default 0,
  operation_run text, operation text check(operation in ('copy','delete'))
);
create index media_backup_copies_retirement on media_backup.copies(retired_at) where state<>'deleted';
alter table media_backup.control enable row level security;
alter table media_backup.copies enable row level security;
revoke all on all tables in schema media_backup from public,anon,authenticated,service_role;

-- Never include unrelated/future buckets automatically. Source reads exclude
-- archived versions and delete markers; last_accessed_at is not a file change.
create view media_backup.source_inventory as
select o.id object_id,o.bucket_id bucket,o.name object_name,o.updated_at source_updated_at,
  (o.metadata->>'size')::bigint byte_size,
  coalesce(o.metadata->>'eTag',o.metadata->>'etag') source_etag,
  encode(sha256(convert_to(jsonb_build_array(o.id,o.bucket_id,o.name,o.version,o.updated_at,
    o.metadata->>'size',coalesce(o.metadata->>'eTag',o.metadata->>'etag'))::text,'UTF8')),'hex') fingerprint
from storage.objects o
where o.bucket_id = any(array['avatars','family_avatars','legacy_avatars','memory_photos','memory_voice',
  'vault_photos','vault_voice','legacy_memory_photos','legacy_memory_voice','legacy_vault_photos','legacy_vault_voice','voice notes'])
  and o.archived_at is null and o.is_delete_marker is not true
  and o.metadata->>'size' ~ '^[0-9]{1,12}$';
revoke all on media_backup.source_inventory from public,anon,authenticated,service_role;

create function public.dispatch_media_backup() returns bigint
language plpgsql security definer set search_path='' as $$
declare c media_backup.control; token text; request_id bigint; stamp timestamptz:=clock_timestamp();
begin
  select * into c from media_backup.control where singleton for update;
  if not c.enabled or c.busy_until>stamp then return null; end if;
  if c.day is distinct from (stamp at time zone 'UTC')::date then
    update media_backup.control set day=(stamp at time zone 'UTC')::date,runs=0,copy_bytes=0 where singleton;
    c.runs:=0;
  end if;
  if c.runs>=288 then return null; end if;
  token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
  update media_backup.control set run_hash=encode(sha256(convert_to(token,'UTF8')),'hex'),
    issued_until=stamp+interval '90 seconds',busy_until=stamp+interval '6 minutes',claimed=false,runs=runs+1 where singleton;
  select net.http_post(url:='https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/media_backup_worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-backup-run-token',token),
    body:='{}'::jsonb,timeout_milliseconds:=10000) into request_id;
  return request_id;
end;$$;

create function public.claim_media_backup_run(p_token text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then return false; end if;
  update media_backup.control set claimed=true,last_run_at=clock_timestamp()
  where singleton and enabled and not claimed and issued_until>clock_timestamp()
    and run_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  return found;
end;$$;

create function media_backup.require_run(p_token text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if p_token is null or p_token !~ '^[a-f0-9]{64}$' then raise exception 'BACKUP_UNAUTHORIZED'; end if;
  perform 1 from media_backup.control where singleton and enabled and claimed and busy_until>clock_timestamp()
    and run_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') for update;
  if not found then raise exception 'BACKUP_UNAUTHORIZED'; end if;
end;$$;

create function public.next_media_backup_work(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c media_backup.control; job media_backup.copies; src record; retained bigint; stamp timestamptz:=clock_timestamp();
begin
  perform media_backup.require_run(p_token);
  select * into c from media_backup.control where singleton;
  -- This is metadata reconciliation only. It never changes a source object.
  update media_backup.copies b set retired_at=stamp where b.state<>'deleted' and b.retired_at is null
    and not exists(select 1 from media_backup.source_inventory s where s.fingerprint=b.fingerprint);
  update media_backup.copies b set retired_at=null where b.state<>'deleted' and b.retired_at is not null
    and exists(select 1 from media_backup.source_inventory s where s.fingerprint=b.fingerprint);
  select * into job from media_backup.copies where state<>'deleted' and
    retired_at < stamp-make_interval(days=>c.retention_days) and attempt_after<=stamp
    order by retired_at,fingerprint limit 1;
  if found then
    -- Never advertise a copy as complete while its remote deletion is in flight.
    update media_backup.copies set state='pending',operation_run=c.run_hash,operation='delete',attempt_after=stamp+interval '1 hour' where fingerprint=job.fingerprint;
    return jsonb_build_object('kind','delete','fingerprint',job.fingerprint);
  end if;
  select s.* into src from media_backup.source_inventory s
    left join media_backup.copies b using(fingerprint)
    where (b.fingerprint is null or b.state='deleted' or (b.state='pending' and b.attempt_after<=stamp))
    order by s.source_updated_at,s.object_id limit 1;
  if not found then return null; end if;
  if src.byte_size>52428800 then
    update media_backup.control set last_error='FILE_TOO_LARGE',last_error_at=stamp where singleton; return null;
  end if;
  if c.day is distinct from (stamp at time zone 'UTC')::date then
    update media_backup.control set day=(stamp at time zone 'UTC')::date,runs=1,copy_bytes=0 where singleton; c.copy_bytes:=0;
  end if;
  if c.copy_bytes+src.byte_size>c.max_daily_copy_bytes then
    update media_backup.control set last_error='DAILY_COPY_LIMIT',last_error_at=stamp where singleton; return null;
  end if;
  -- Reserve metadata overhead too: at most 16 KiB per recovery sidecar and
  -- 31 daily indexes of at most 8 MiB, leaving room for lifecycle processing.
  select coalesce(sum(byte_size+16384),0)+31*8388608 into retained from media_backup.copies where state<>'deleted';
  if not exists(select 1 from media_backup.copies where fingerprint=src.fingerprint and state<>'deleted')
    and (select count(*) from media_backup.copies where state<>'deleted')>=50000 then
    update media_backup.control set last_error='BACKUP_OBJECT_LIMIT',last_error_at=stamp where singleton; return null;
  end if;
  if not exists(select 1 from media_backup.copies where fingerprint=src.fingerprint and state<>'deleted')
    and retained+src.byte_size+16384>c.max_retained_bytes then
    update media_backup.control set last_error='BACKUP_STORAGE_LIMIT',last_error_at=stamp where singleton; return null;
  end if;
  insert into media_backup.copies(fingerprint,object_id,bucket,object_name,source_updated_at,byte_size,source_etag)
    values(src.fingerprint,src.object_id,src.bucket,src.object_name,src.source_updated_at,src.byte_size,src.source_etag)
    on conflict(fingerprint) do update set state='pending',deleted_at=null;
  -- Reserve before any source download. Ambiguous failures are not refunded.
  update media_backup.control set copy_bytes=copy_bytes+src.byte_size where singleton;
  update media_backup.copies set operation_run=c.run_hash,operation='copy',attempts=attempts+1,
    attempt_after=stamp+interval '1 hour' where fingerprint=src.fingerprint;
  return to_jsonb(src)||jsonb_build_object('kind','copy');
end;$$;

create function public.complete_media_backup_work(p_token text,p_fingerprint text,p_sha256 text default null,p_md5 text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare c media_backup.control; job media_backup.copies;
begin
  perform media_backup.require_run(p_token);select * into c from media_backup.control where singleton;
  select * into job from media_backup.copies where fingerprint=p_fingerprint and operation_run=c.run_hash for update;
  if not found then return false; end if;
  if job.operation='delete' then
    -- Recheck before acknowledging. Source content is never deleted by this job.
    if exists(select 1 from media_backup.source_inventory where fingerprint=p_fingerprint) then
      update media_backup.copies set state='pending',attempt_after=clock_timestamp(),retired_at=null,
        operation=null,operation_run=null where fingerprint=p_fingerprint;
      return false;
    end if;
    update media_backup.copies set state='deleted',deleted_at=clock_timestamp(),operation=null,operation_run=null where fingerprint=p_fingerprint;
  elsif job.operation='copy' then
    if p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' or p_md5 is null or p_md5 !~ '^[a-f0-9]{32}$' then raise exception 'BACKUP_INVALID_CHECKSUM'; end if;
    -- A change during transfer is retained as an old version, never advertised
    -- as the current version. Its new fingerprint will be copied separately.
    update media_backup.copies set state='complete',sha256=p_sha256,md5=p_md5,copied_at=clock_timestamp(),
      operation=null,operation_run=null where fingerprint=p_fingerprint;
  else return false; end if;
  update media_backup.control set last_complete_at=clock_timestamp() where singleton;
  return true;
end;$$;

create function public.media_backup_manifest(p_token text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; c media_backup.control;
begin
  perform media_backup.require_run(p_token); select * into c from media_backup.control where singleton;
  if c.last_manifest_at > date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC' then return null; end if;
  select jsonb_build_object('format',1,'project','vbzyvaylfdhwowdbodmk','captured_at',clock_timestamp(),
    'missing',count(*) filter(where b.state is distinct from 'complete'),
    'entries',coalesce(jsonb_agg(jsonb_build_object('fingerprint',s.fingerprint,'bucket',s.bucket,
      'object_name',s.object_name,'object_id',s.object_id,'source_updated_at',s.source_updated_at,
      'byte_size',s.byte_size,'sha256',b.sha256,'md5',b.md5)) filter(where b.state='complete'),'[]'::jsonb)) into result
    from media_backup.source_inventory s left join media_backup.copies b using(fingerprint);
  -- Unexpected/malformed objects must prevent a false complete manifest.
  if exists(select 1 from storage.objects o where o.archived_at is null and o.is_delete_marker is not true
    and not exists(select 1 from media_backup.source_inventory s where s.object_id=o.id)) then
    update media_backup.control set last_error='INVENTORY_INCOMPLETE',last_error_at=clock_timestamp() where singleton; return null;
  end if;
  if octet_length(result::text)>8388608 then
    update media_backup.control set last_error='MANIFEST_LIMIT',last_error_at=clock_timestamp() where singleton; return null;
  end if;
  return result;
end;$$;

create function public.media_backup_source_current(p_token text,p_fingerprint text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform media_backup.require_run(p_token);
  return exists(select 1 from media_backup.source_inventory where fingerprint=p_fingerprint);
end;$$;

create function public.finish_media_backup_run(p_token text,p_error text default null,p_manifest boolean default false)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform media_backup.require_run(p_token);
  if p_error is not null and p_error not in ('SOURCE_FAILED','DESTINATION_FAILED','VERIFY_FAILED','BACKUP_UNAVAILABLE') then raise exception 'BACKUP_INVALID_ERROR'; end if;
  update media_backup.control set busy_until=null,claimed=false,run_hash=null,issued_until=null,
    last_error=case when p_error is not null then p_error when p_manifest then null else last_error end,
    last_error_at=case when p_error is not null then clock_timestamp() when p_manifest then null else last_error_at end,
    last_manifest_at=case when p_manifest then clock_timestamp() else last_manifest_at end where singleton;
  delete from media_backup.copies where state='deleted' and deleted_at<clock_timestamp()-interval '7 days';
  return true;
end;$$;

revoke all on all functions in schema media_backup from public,anon,authenticated,service_role;
revoke all on function public.dispatch_media_backup(),public.claim_media_backup_run(text),public.next_media_backup_work(text),
  public.complete_media_backup_work(text,text,text,text),public.media_backup_manifest(text),public.finish_media_backup_run(text,text,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.dispatch_media_backup(),public.claim_media_backup_run(text),public.next_media_backup_work(text),
  public.complete_media_backup_work(text,text,text,text),public.media_backup_manifest(text),public.finish_media_backup_run(text,text,boolean)
  to service_role;
revoke all on function public.media_backup_source_current(text,text) from public,anon,authenticated,service_role;
grant execute on function public.media_backup_source_current(text,text) to service_role;

create function public.business_media_backup_status() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  perform heiro_business.require_owner();
  select jsonb_build_object('enabled',c.enabled,'last_run_at',c.last_run_at,'last_manifest_at',c.last_manifest_at,
    'last_error',c.last_error,'retained_bytes',(select coalesce(sum(byte_size),0) from media_backup.copies where state<>'deleted'),
    'limit_bytes',c.max_retained_bytes,'daily_limit_bytes',c.max_daily_copy_bytes,
    'pending',(select count(*) from media_backup.source_inventory s where not exists(select 1 from media_backup.copies b where b.fingerprint=s.fingerprint and b.state='complete')),
    'stale',c.last_manifest_at is null or c.last_manifest_at<clock_timestamp()-interval '36 hours') into result
  from media_backup.control c where singleton;
  return result;
end;$$;
revoke all on function public.business_media_backup_status() from public,anon,authenticated,service_role;
grant execute on function public.business_media_backup_status() to authenticated;
-- Activation and scheduling are intentionally separate from installation.
