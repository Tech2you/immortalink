import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = (name) => readFile(new URL(`../../migrations/${name}.sql`,import.meta.url),'utf8');
export const ids=Array.from({length:20},(_,n)=>`00000000-0000-4000-8000-${String(n+1).padStart(12,'0')}`);
export const [owner,viewer,family,legacy,vault,memory,sibling,legacyMemory,lease]=ids;
export const photoPath=`${owner}/${vault}/memories/${memory}/photo.png`;
export const audioPath=`${owner}/${vault}/memories/${memory}/voice.m4a`;
export const siblingPath=`${owner}/${vault}/memories/${sibling}/photo.png`;
export const legacyPath=`${owner}/${family}/legacy/${legacy}/memories/${legacyMemory}/photo.png`;
export const legacyAudio=`${owner}/${family}/legacy/${legacy}/memories/${legacyMemory}/voice.m4a`;
export async function fixture(db=new PGlite()) {
  await db.exec(`do $$ begin
      if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
      if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
      if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
    end $$;
    create schema auth;create schema storage;
    create table storage.buckets(id text primary key,public boolean default false,versioning_status text default 'DISABLED');
    insert into storage.buckets(id) values('vault_photos'),('memory_photos'),('memory_voice'),('legacy_memory_photos'),('legacy_memory_voice');
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',coalesce(nullif(current_setting('test.role',true),''),'service_role'))$$;
    create table auth.users(id uuid primary key);
    create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
    create table family_groups(id uuid primary key,created_by uuid,name text);
    create table family_members(family_id uuid,user_id uuid,role text,joined_at timestamptz default now());
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid,display_name text,name text,avatar_path text,created_at timestamptz default now());
    create table memories(id uuid primary key,vault_id uuid,prompt_text text,body text);
    create table family_relationships(family_id uuid,parent_type text,parent_id uuid,child_type text,child_id uuid);
    create table family_links(family_id uuid);
    create table family_invites(family_id uuid,created_by uuid,inviter_vault_id uuid);
    create table family_feed_hidden_vaults(user_id uuid,hidden_vault_id uuid);
    create table legacy_family_members(id uuid primary key,family_id uuid,created_by uuid,avatar_path text,name text,display_name text,about_me_text text);
    create table legacy_memories(id uuid primary key,legacy_member_id uuid references legacy_family_members on delete cascade,family_id uuid,prompt_text text,body text);
    create table legacy_memory_chunks(id uuid,legacy_member_id uuid references legacy_family_members on delete cascade,legacy_memory_id uuid);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,
      metadata jsonb default '{"size":10,"mimetype":"image/png"}',created_at timestamptz default now(),updated_at timestamptz default now(),unique(bucket_id,name));
    create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
    create function everroot_media_bucket_ids() returns text[] language sql as $$select array['vault_photos','memory_photos','memory_voice','legacy_memory_photos','legacy_memory_voice']$$;
    create function everroot_storage_metadata_size(jsonb) returns bigint language sql as $$select coalesce(($1->>'size')::bigint,0)$$;
    create function everroot_try_uuid(text) returns uuid language sql as $$select $1::uuid$$;
    create function everroot_quota_error(text,text) returns void language plpgsql as $$begin raise exception '%',$1;end;$$;
    create function everroot_assert_family_writable(uuid) returns void language plpgsql as $$begin
      if current_setting('test.expired',true)='true' then raise exception 'FAMILY_EXPIRED';end if;end;$$;
    create function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1000::bigint$$;
    create function everroot_storage_bytes_used(uuid,uuid) returns bigint language sql as $$select
      case when current_setting('test.full',true)='true' then 1000 else 0 end::bigint$$;
    create function can_read_vault_media(uuid) returns boolean language sql as $$select false$$;
    create function everroot_assert_storage_capacity(uuid,uuid,text) returns void language plpgsql as $$begin
      perform everroot_assert_family_writable($1);end;$$;
    insert into auth.users values('${owner}'),('${viewer}');
    insert into family_groups values('${family}','${owner}','QA');
    insert into family_members(family_id,user_id,role) values('${family}','${owner}','owner'),('${family}','${viewer}','member');
    insert into vaults(id,owner_id,family_id,name) values('${vault}','${owner}','${family}','QA');
    insert into memories values('${memory}','${vault}','QA','Reported'),('${sibling}','${vault}','QA','Sibling');
    insert into legacy_family_members(id,family_id,created_by,name) values('${legacy}','${family}','${owner}','Grandma');
    insert into legacy_memories values('${legacyMemory}','${legacy}','${family}','QA','Legacy');`);
  for(const table of ['legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note']) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid() primary key,legacy_member_id uuid references legacy_family_members on delete cascade,
      legacy_memory_id uuid,path text,family_id uuid);`);
  }
  for(const table of ['memory_voice_notes','memory_photos','memory_chunks','vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes']) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid() primary key,memory_id uuid,vault_id uuid,path text,title text,created_at timestamptz default now());`);
  }
  await db.exec(`insert into memory_photos(vault_id,memory_id,path) values('${vault}','${memory}','${photoPath}'),('${vault}','${sibling}','${siblingPath}');
    insert into memory_voice_notes(vault_id,memory_id,path) values('${vault}','${memory}','${audioPath}');
    insert into legacy_memory_photos(legacy_member_id,legacy_memory_id,path,family_id) values('${legacy}','${legacyMemory}','${legacyPath}','${family}');
    insert into legacy_memory_voice_notes(legacy_member_id,legacy_memory_id,path,family_id) values('${legacy}','${legacyMemory}','${legacyAudio}','${family}');`);
  for(const [bucket,path] of [['vault_photos',photoPath],['memory_voice',audioPath],['vault_photos',siblingPath],['vault_photos',legacyPath],['legacy_memory_voice',legacyAudio]]) {
    await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values($1,$2,$3::uuid,$3,$4)',
      [bucket,path,owner,{size:10,contentLength:10,eTag:'fixture-content-hash',lastModified:'2026-10-22T10:00:00Z',
        cacheControl:'max-age=3600',httpStatusCode:200,mimetype:path.endsWith('.m4a')?'audio/mp4':'image/png'}]);
  }
  for(const name of ['20260928212919_family_owner_successor','20260809111000_fix_everroot_legacy_media_column_detection',
    '20261001225542_deletion_media_preservation','20261007213340_media_reference_authorization',
    '20261013104043_family_content_safety','20261013122650_safety_attribution_deletion_cleanup','20261018210222_content_report_case_preview',
    '20261021102247_personal_memory_reports','20261022213230_memory_insert_returning_safety','20261023101256_memory_media_retirement']) {
    await db.exec(await migration(name));
  }
  await db.exec(`create trigger everroot_storage_object_capacity_before_write before insert or update on storage.objects
    for each row execute function everroot_assert_storage_object_capacity();
    grant usage on schema auth,storage to service_role,authenticated;
    grant all on all tables in schema public,storage to service_role;
    grant select,insert,update on storage.objects to authenticated;`);
  return db;
}
export async function report(db,kind='memory') {
  return (await db.query(`insert into content_reports(reporter_id,family_id,target_kind,target_id,subject_user_id,reason,details)
    values($1,$2,$3,$4,$5,'other','Disposable QA') returning id`,[viewer,family,kind,kind==='memory'?memory:legacyMemory,owner])).rows[0].id;
}
export async function act(db,id,action) {
  const data=(await db.query("select preview_content_report($1,'QA') data",[id])).rows[0].data;
  return db.query("select review_content_report_checked($1,$2,'QA','Disposable QA',$3)",[id,action,data.revision]);
}
export async function next(db,id) {
  return (await db.query('select next_content_media_retirement($1) data',[id])).rows[0].data;
}
export async function status(db,id) {
  return (await db.query('select content_report_media_status($1) data',[id])).rows[0].data;
}
export async function move(db,job) {
  // Simulates only Storage's atomic metadata commit, not its external byte API.
  return db.query("update storage.objects set name=$1,owner=null,owner_id=null,updated_at=now(),metadata=jsonb_set(metadata,'{lastModified}',to_jsonb(clock_timestamp())) where bucket_id=$2 and name=$3 returning id",
    [job.destination,job.bucket,job.source]);
}
export async function finish(db,id) {
  for(let n=0;n<10;n++){const job=await next(db,id);if(!job)return;await move(db,job);}
  throw new Error('Unbounded retirement');
}
