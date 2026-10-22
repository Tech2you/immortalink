import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const read = (name) => readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');
const migration = await read('20261001225542_deletion_media_preservation.sql');
const mediaAuthorization = await read('20261007213340_media_reference_authorization.sql');
const successor = await read('20260928212919_family_owner_successor.sql');
const cleanup = await read('20260809111000_fix_everroot_legacy_media_column_detection.sql');
const ids = Array.from({length:8},(_,n)=>`00000000-0000-4000-8000-${String(n+1).padStart(12,'0')}`);
const [a,b,f,l,v,m,lease,session]=ids;
async function fixture() {
  const db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role;
    create schema auth;create schema storage;
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',coalesce(nullif(current_setting('test.role',true),''),'service_role'))$$;
    create table auth.users(id uuid primary key);
    create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
    create table family_groups(id uuid primary key,created_by uuid);
    create table family_members(family_id uuid,user_id uuid,role text,joined_at timestamptz default now());
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid,display_name text,name text,created_at timestamptz default now());
    create table memories(id uuid primary key,vault_id uuid);
    create table family_relationships(family_id uuid,parent_type text,parent_id uuid,child_type text,child_id uuid);
    create table family_links(family_id uuid);
    create table family_invites(family_id uuid,created_by uuid,inviter_vault_id uuid);
    create table family_feed_hidden_vaults(user_id uuid,hidden_vault_id uuid);
    create table legacy_family_members(id uuid primary key,family_id uuid,created_by uuid,avatar_path text);
    create table legacy_memories(id uuid primary key,legacy_member_id uuid references legacy_family_members on delete cascade,family_id uuid);
    create table legacy_memory_chunks(id uuid,legacy_member_id uuid references legacy_family_members on delete cascade);
    create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text,metadata jsonb,unique(bucket_id,name));
    create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
    create function everroot_media_bucket_ids() returns text[] language sql as $$select array['vault_photos','memory_voice']$$;
    create function everroot_storage_metadata_size(jsonb) returns bigint language sql as $$select coalesce(($1->>'size')::bigint,0)$$;
    create function everroot_try_uuid(text) returns uuid language sql as $$select $1::uuid$$;
    create function everroot_quota_error(text,text) returns void language plpgsql as $$begin raise exception '%',$1;end;$$;
    create function everroot_assert_family_writable(uuid) returns void language plpgsql as $$begin
      if current_setting('test.overquota',true)='true' then raise exception 'over quota';end if;end;$$;
    create function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1000::bigint$$;
    create function everroot_storage_bytes_used(uuid,uuid) returns bigint language sql as $$select 0::bigint$$;
    create function can_read_vault_media(uuid) returns boolean language sql as $$select false$$;
    create function everroot_assert_storage_capacity(uuid,uuid,text) returns void language plpgsql as $$begin
      perform everroot_assert_family_writable($1);end;$$;
    insert into auth.users values('${a}'),('${b}');
    insert into auth.sessions values('${session}','${a}',null);
    insert into family_groups values('${f}','${a}');
    insert into family_members(family_id,user_id,role) values('${f}','${a}','owner'),('${f}','${b}','member');
    insert into vaults(id,owner_id,family_id) values('${v}','${a}','${f}');
    insert into memories values('${m}','${v}');
    insert into legacy_family_members values('${l}','${f}','${a}','${a}/${f}/avatar');
    insert into legacy_memories values('${m}','${l}','${f}');
    insert into legacy_memory_chunks values('${m}','${l}');
    insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values
      ('vault_photos','${a}/${f}/avatar','${a}','${a}','{"size":10}'),
      ('vault_photos','${a}/${v}/private','${a}','${a}','{"size":20}');`);
  for(const table of ['legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note']) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid() primary key,legacy_member_id uuid references legacy_family_members on delete cascade,path text,family_id uuid);`);
  }
  for(const table of ['memory_voice_notes','memory_photos','memory_chunks']) await db.exec(`create table ${table}(memory_id uuid);`);
  for(const table of ['vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes']) await db.exec(`create table ${table}(vault_id uuid);`);
  await db.exec(successor);
  await db.exec(cleanup);
  await db.exec(migration);
  await db.exec(mediaAuthorization);
  await db.exec(`create trigger capacity before insert or update on storage.objects for each row execute function everroot_assert_storage_object_capacity();
    create trigger avatar_capacity before update of avatar_path on legacy_family_members for each row execute function everroot_assert_legacy_avatar_storage_capacity();`);
  return db;
}
const claim = (db,token=lease) => db.query('select claim_account_deletion($1,$2)',[a,token]);
const finalize = (db,token=lease) => db.query('select finalize_account_deletion_data($1,$2)',[a,token]);
async function copy(db) {
  await db.exec(`insert into storage.objects(bucket_id,name,metadata)
    select bucket_id,target_path,jsonb_build_object('size',size_bytes) from account_deletion_files where target_path is not null;`);
}
test('missing copy stops all deletion; complete copy preserves legacy ownership and bytes even over quota',async()=>{
  const db=await fixture();try{
    await claim(db);
    await assert.rejects(finalize(db),/COPY_REQUIRED/);
    assert.equal((await db.query('select * from vaults')).rows.length,1);
    assert.equal((await db.query('select * from family_members')).rows.length,2);
    await db.exec("select set_config('test.overquota','true',false)");
    await copy(db);
    await finalize(db);
    assert.equal((await db.query('select * from vaults')).rows.length,0);
    assert.deepEqual((await db.query('select user_id,role from family_members')).rows,[{user_id:b,role:'owner'}]);
    const shared=(await db.query('select * from legacy_family_members')).rows[0];
    assert.equal(shared.created_by,b);
    assert.equal(shared.avatar_path.startsWith(a+'/'),false);
    assert.equal((await db.query('select * from legacy_memories')).rows.length,1);
    assert.equal((await db.query('select * from storage.objects')).rows.length,3);
    assert.equal((await db.query('select account_deletion_storage_clean($1,$2) ok',[a,lease])).rows[0].ok,false);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    assert.equal((await db.query('select account_deletion_storage_clean($1,$2) ok',[a,lease])).rows[0].ok,true);
    assert.equal((await db.query('select * from storage.objects')).rows.length,1);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    assert.equal((await db.query("select can_read_legacy_gallery_object('vault_photos',$1) ok",[shared.avatar_path])).rows[0].ok,true);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    assert.equal((await db.query("select can_read_legacy_gallery_object('vault_photos',$1) ok",[shared.avatar_path])).rows[0].ok,false);
  }finally{await db.close();}
});
test('last member cleanup removes tree and includes its retained copies in byte cleanup',async()=>{
  const db=await fixture();try{
    await db.query('delete from family_members where user_id=$1',[b]);
    await claim(db);await copy(db);await finalize(db);
    assert.equal((await db.query('select * from family_groups')).rows.length,0);
    assert.equal((await db.query('select * from legacy_family_members')).rows.length,0);
    assert.equal((await db.query('select * from legacy_memory_chunks')).rows.length,0);
    assert.equal((await db.query('select * from account_deletion_files')).rows.length,3);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await finalize(db);
  }finally{await db.close();}
});
test('both contributors keep Grandma content when a non-creator deletes their account',async()=>{
  const db=await fixture();try{
    await db.query('update legacy_family_members set created_by=$1',[b]);
    for (const user of [a,b]) {
      const path=`${user}/${f}/legacy/${l}/gallery/photo`;
      await db.query("insert into storage.objects(bucket_id,name,owner_id,metadata) values('vault_photos',$1,$2,'{\"size\":15}')",[path,user]);
      await db.query('insert into legacy_member_photos(legacy_member_id,path,family_id) values($1,$2,$3)',[l,path,f]);
    }
    await claim(db);await copy(db);await finalize(db);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    const photos=(await db.query('select path from legacy_member_photos')).rows;
    assert.equal(photos.length,2);
    assert.equal(photos.some(row=>row.path.startsWith(a+'/')),false);
    assert.equal(photos.some(row=>row.path.startsWith(b+'/')),true);
    assert.equal((await db.query('select created_by from legacy_family_members')).rows[0].created_by,b);
    assert.equal((await db.query('select * from vaults')).rows.length,0);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    for(const {path} of photos) {
      assert.equal((await db.query("select can_read_legacy_gallery_object('vault_photos',$1) ok",[path])).rows[0].ok,true);
      assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,1);
    }
  }finally{await db.close();}
});
test('leases prevent concurrent workers; private RPCs and jobs cannot be called or changed by clients',async()=>{
  const db=await fixture();try{
    await claim(db);
    await assert.rejects(claim(db,b),/BUSY/);
    await assert.rejects(finalize(db,b),/LEASE_LOST/);
    await db.exec("update account_deletion_jobs set lease_until=now()-interval '1 second'");
    await assert.rejects(finalize(db),/LEASE_LOST/);
    await claim(db,b);
    for(const role of ['anon','authenticated']){
      assert.equal((await db.query("select has_function_privilege($1,'claim_account_deletion(uuid,uuid)','execute') ok",[role])).rows[0].ok,false);
      assert.equal((await db.query("select has_table_privilege($1,'account_deletion_files','select') ok",[role])).rows[0].ok,false);
    }
  }finally{await db.close();}
});
test('deleting users cannot upload or join, other members cannot reattach their files, quota exception is service-only',async()=>{
  const db=await fixture();try{
    await claim(db);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.exec("select set_config('test.role','authenticated',false)");
    await assert.rejects(db.query("insert into family_members(family_id,user_id,role) values($1,$2,'owner')",[f,a]),/DELETION_IN_PROGRESS/);
    await assert.rejects(copy(db),/DELETION_IN_PROGRESS/);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    await assert.rejects(db.query('insert into legacy_member_photos(legacy_member_id,path,family_id) values($1,$2,$3)',[l,`${a}/${f}/avatar`,f]),/MEDIA_ACCOUNT_DELETION/);
    await db.exec("select set_config('test.overquota','true',false)");
    await assert.rejects(copy(db),/MEDIA_ACCOUNT_DELETION_IN_PROGRESS/);
    assert.equal((await db.query("select deletion_copy_authorized(bucket_id,target_path,size_bytes) ok from account_deletion_files where target_path is not null")).rows[0].ok,false);
    assert.equal((await db.query('select account_deletion_session_current($1,$2) ok',[a,session])).rows[0].ok,true);
    await db.exec('delete from auth.sessions');
    assert.equal((await db.query('select account_deletion_session_current($1,$2) ok',[a,session])).rows[0].ok,false);
  }finally{await db.close();}
});
test('family avatar rehoming retains its fixed URL and refuses to finalize before the replacement copy exists',async()=>{
  const db=await fixture();try{
    await db.query("insert into storage.objects(bucket_id,name,owner,owner_id,metadata) values('family_avatars',$1,$2::text::uuid,$2::text,'{\"size\":30}')",[`${f}/avatar`,a]);
    await claim(db);await copy(db);
    await assert.rejects(finalize(db),/REHOME_REQUIRED/);
    await db.query("delete from storage.objects where bucket_id='family_avatars' and name=$1",[`${f}/avatar`]);
    await assert.rejects(finalize(db),/REHOME_REQUIRED/);
    await db.exec("insert into storage.objects(bucket_id,name,metadata) select bucket_id,source_path,jsonb_build_object('size',size_bytes) from account_deletion_files where keep_source");
    await finalize(db);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=case when f.keep_source then f.target_path else f.source_path end');
    assert.equal((await db.query("select name,owner_id from storage.objects where bucket_id='family_avatars'")).rows[0].name,`${f}/avatar`);
    assert.equal((await db.query('select account_deletion_storage_clean($1,$2) ok',[a,lease])).rows[0].ok,true);
  }finally{await db.close();}
});
test('retained legacy bytes stay manageable by surviving members without exposing private media',async()=>{
  const db=await fixture();try{
    await claim(db);await copy(db);await finalize(db);
    await db.exec(`alter table storage.objects enable row level security;
      grant usage on schema storage,auth to authenticated;
      grant select,delete on storage.objects to authenticated;
      select set_config('test.role','authenticated',false);set role authenticated;`);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    assert.equal((await db.query('select * from storage.objects')).rows.length,1);
    await db.exec('delete from storage.objects');
    await db.exec('reset role');
    assert.equal((await db.query('select * from storage.objects')).rows.length,2);
  }finally{await db.close();}
});
