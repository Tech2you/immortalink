import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = async (name) => readFile(new URL(`../migrations/${name}.sql`, import.meta.url), 'utf8');
const foundation = await migration('20261013104043_family_content_safety');
const previews = await migration('20261018210222_content_report_case_preview');
const personal = await migration('20261021102247_personal_memory_reports');
const insertSafety = await migration('20261022213230_memory_insert_returning_safety');
const references = await migration('20261007213340_media_reference_authorization');
const scope = references.split('create function public.guard_media_reference_scope()')[0];
const ids = Array.from({length: 20}, (_, n) => `00000000-0000-4000-8000-${String(n+1).padStart(12,'0')}`);
const [owner, viewer, outsider, family, otherFamily, vault, otherVault, memory, sibling,
  foreignMemory, photo, audio, siblingPhoto, legacy, legacyMemory, legacyPhoto, sharedFamily] = ids;
const photoPath = `${owner}/${vault}/memories/${memory}/photo.jpg`;
const audioPath = `${owner}/${vault}/memories/${memory}/voice.m4a`;
const siblingPath = `${owner}/${vault}/memories/${sibling}/other.jpg`;
const legacyPath = `${owner}/${family}/legacy/${legacy}/memories/${legacyMemory}/photo.jpg`;

async function fixture({applyInsertFix=true}={}) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql as $$select '{"role":"authenticated"}'::jsonb$$;
    create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
    create table storage.objects(id uuid primary key,bucket_id text,name text,owner uuid,owner_id text,
      created_at timestamptz default now(),updated_at timestamptz default now(),metadata jsonb default '{}');
    create table family_groups(id uuid primary key,name text);
    create table family_members(family_id uuid,user_id uuid references auth.users(id) on delete cascade);
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid,name text,display_name text,avatar_path text,created_at timestamptz default now());
    create table memories(id uuid primary key,vault_id uuid,prompt_text text,body text);
    create table legacy_family_members(id uuid primary key,family_id uuid,name text,display_name text,about_me_text text,avatar_path text);
    create table legacy_memories(id uuid primary key,legacy_member_id uuid,family_id uuid,prompt_text text,body text);
    create table legacy_memory_chunks(id uuid,legacy_member_id uuid,legacy_memory_id uuid);
    insert into auth.users values('${owner}'),('${viewer}'),('${outsider}');
    insert into family_groups values('${family}','Family'),('${otherFamily}','Other'),('${sharedFamily}','Shared');
    insert into family_members values('${family}','${owner}'),('${family}','${viewer}'),('${otherFamily}','${outsider}');
    insert into vaults(id,owner_id,family_id,name) values('${vault}','${owner}','${family}','Owner'),('${otherVault}','${outsider}','${otherFamily}','Outsider');
    insert into memories values('${memory}','${vault}','Memory','Reported text'),('${sibling}','${vault}','Other memory','UNREPORTED PRIVATE TEXT'),('${foreignMemory}','${otherVault}','Other family','FOREIGN TEXT');
    insert into legacy_family_members values('${legacy}','${family}','Grandma',null,'Profile only',null);
    insert into legacy_memories values('${legacyMemory}','${legacy}','${family}','Legacy memory','Shared legacy text');`);
  const personalTables = ['memory_photos','memory_voice_notes','memory_chunks','vault_highlight_photos',
    'vault_about_photos','vault_core_voice_note','vault_voice_notes','voice_notes','vault_media'];
  const legacyTables = ['legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes',
    'legacy_vault_about_photos','legacy_vault_core_voice_note'];
  for (const table of personalTables) {
    await db.exec(`create table ${table}(id uuid primary key default gen_random_uuid(),vault_id uuid,memory_id uuid,path text,title text,created_at timestamptz default now());`);
  }
  for (const table of legacyTables) {
    await db.exec(`create table ${table}(id uuid primary key default gen_random_uuid(),family_id uuid,legacy_member_id uuid,legacy_memory_id uuid,path text);`);
  }
  await db.exec(`insert into memory_photos(id,vault_id,memory_id,path) values('${photo}','${vault}','${memory}','${photoPath}'),('${siblingPhoto}','${vault}','${sibling}','${siblingPath}');
    insert into memory_voice_notes(id,vault_id,memory_id,path) values('${audio}','${vault}','${memory}','${audioPath}');
    insert into memory_chunks(vault_id,memory_id) values('${vault}','${memory}'),('${vault}','${sibling}');
    insert into legacy_memory_photos values('${legacyPhoto}','${family}','${legacy}','${legacyMemory}','${legacyPath}');
    insert into storage.objects(id,bucket_id,name,owner,owner_id) values
      ('${photo}','vault_photos','${photoPath}','${owner}','${owner}'),
      ('${audio}','memory_voice','${audioPath}','${owner}','${owner}'),
      ('${siblingPhoto}','vault_photos','${siblingPath}','${owner}','${owner}'),
      ('${legacyPhoto}','vault_photos','${legacyPath}','${owner}','${owner}');
    grant usage on schema auth,storage to authenticated,anon,service_role;
    grant select on all tables in schema public to authenticated;
    grant select on storage.objects to authenticated;`);
  // Broad existing read policies cannot bypass the added restrictive ceilings.
  for (const table of [...personalTables,...legacyTables,'memories','vaults','legacy_memories','legacy_family_members','legacy_memory_chunks','storage.objects']) {
    await db.exec(`alter table ${table} enable row level security;
      create policy fixture_read on ${table} for select to authenticated using(true);`);
  }
  await db.exec(foundation + scope + previews + personal);
  if (applyInsertFix) await db.exec(insertSafety);
  await asUser(db, viewer);
  return db;
}
async function asUser(db, id) {
  await db.exec('reset role; set role authenticated');
  await db.query("select set_config('test.uid',$1,false)", [id]);
}
async function report(db, id = memory, familyId = null, kind = 'memory') {
  return (await db.query("select report_family_content($1,$2,'other','Harmless QA photo',$3) id", [kind,id,familyId])).rows[0].id;
}
async function preview(db, reportId) {
  await db.exec('reset role; set role service_role');
  return (await db.query("select preview_content_report($1,'QA operator') data", [reportId])).rows[0].data;
}
async function decision(db, reportId, action) {
  const data = await preview(db, reportId);
  await db.query("select review_content_report_checked($1,$2,'QA operator','Harmless QA test',$3)", [reportId,action,data.revision]);
}

async function enableOwnerWrites(db) {
  await db.exec(`reset role;
    alter table memories alter column id set default gen_random_uuid();
    grant insert,update on memories to authenticated;
    create policy fixture_insert_owner on memories for insert to authenticated
      with check(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));
    create policy fixture_update_owner on memories for update to authenticated
      using(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()))
      with check(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));`);
  await asUser(db,owner);
}

// PostgREST requests a RETURNING row for Dart's insert(...).select('id').single().
async function insertReturning(db, targetVault=vault) {
  return (await db.query(`with pgrst_source as (
    insert into memories(vault_id,prompt_text,body) values($1,'QA','Harmless memory') returning id
  ) select id from pgrst_source`,[targetVault])).rows;
}

test('pre-fix SELECT policy reproduces and rolls back the insert-returning failure', async () => {
  const db=await fixture({applyInsertFix:false}); try {
    await enableOwnerWrites(db);
    await assert.rejects(insertReturning(db),/row-level security policy "safety_memory_read"/);
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int n from memories')).rows[0].n,3);
  } finally {await db.close();}
});

test('owners can create a memory and return its generated ID in the same statement', async () => {
  const db=await fixture(); try {
    await enableOwnerWrites(db);
    const rows=await insertReturning(db);
    assert.equal(rows.length,1);
    assert.ok(rows[0].id);
    assert.equal((await db.query('select body from memories where id=$1',[rows[0].id])).rows[0].body,'Harmless memory');
    const updated=await db.query("update memories set body='Edited QA' where id=$1 returning id,body",[rows[0].id]);
    assert.equal(updated.rows[0].body,'Edited QA');
    for (const table of ['memory_photos','memory_voice_notes']) {
      await db.exec(`reset role; grant insert on ${table} to authenticated;
        create policy fixture_insert_owner on ${table} for insert to authenticated
          with check(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));`);
      await asUser(db,owner);
      assert.equal((await db.query(`insert into ${table}(vault_id,memory_id,path)
        values($1,$2,$3) returning id`,[vault,rows[0].id,`${owner}/${vault}/memories/${rows[0].id}/qa`])).rows.length,1);
    }
    await asUser(db,viewer);
    assert.ok(await report(db,rows[0].id));
  } finally {await db.close();}
});

test('insert-returning fix grants no writes to relatives, outsiders or anonymous users', async () => {
  const db=await fixture(); try {
    await enableOwnerWrites(db);
    await assert.rejects(insertReturning(db,otherVault),/row-level security/);
    for (const user of [viewer,outsider]) {
      await asUser(db,user);
      await assert.rejects(insertReturning(db),/row-level security/);
      assert.equal((await db.query("update memories set body='forged' where id=$1 returning id",[memory])).rows.length,0);
    }
    await db.exec('reset role; set role anon');
    await assert.rejects(insertReturning(db),/permission denied/);
  } finally {await db.close();}
});

test('insert-returning fix keeps hidden memory IDs, vaults and suspended contributors restricted', async () => {
  const db=await fixture(); try {
    const id=await report(db);
    await decision(db,id,'hide');
    await enableOwnerWrites(db);
    assert.equal((await db.query("update memories set body='hidden edit' where id=$1 returning id",[memory])).rows.length,0);
    // A prior restriction cannot be bypassed by recreating its target ID.
    await db.exec('reset role');
    await db.query("insert into content_safety.restrictions(target_kind,target_id) values('memory',$1)",[ids[19]]);
    await asUser(db,owner);
    await assert.rejects(db.query('insert into memories(id,vault_id,body) values($1,$2,$3) returning id',
      [ids[19],vault,'restricted ID']),/row-level security/);
    await decision(db,id,'restore');
    await asUser(db,owner);
    assert.equal((await db.query("update memories set body='Restored QA' where id=$1 returning id",[memory])).rows.length,1);
    await db.exec('reset role');
    await db.query("insert into content_safety.restrictions(target_kind,target_id) values('vault',$1)",[vault]);
    await asUser(db,owner);await assert.rejects(insertReturning(db),/row-level security/);
    await db.exec('reset role');
    await db.query("delete from content_safety.restrictions where target_kind='vault' and target_id=$1",[vault]);
    await decision(db,id,'suspend');
    await asUser(db,owner);await assert.rejects(insertReturning(db),/SAFETY_ACCOUNT_RESTRICTED/);
    await decision(db,id,'reinstate');
    await asUser(db,owner);assert.equal((await insertReturning(db)).length,1);
  } finally {await db.close();}
});

test('personal reports bind exact memory, author and family; duplicates and permissions remain enforced', async () => {
  const db=await fixture(); try {
    const id=await report(db);
    assert.equal(await report(db),id);
    const rows=(await db.query('select * from content_reports')).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].target_kind,'memory');
    assert.equal(rows[0].target_id,memory);assert.equal(rows[0].subject_user_id,owner);assert.equal(rows[0].family_id,family);
    assert.equal((await db.query('select * from memories where id=$1',[memory])).rows.length,1);
    await assert.rejects(report(db,foreignMemory),/CONTENT_UNAVAILABLE/);
    await assert.rejects(report(db,memory,otherFamily),/CONTENT_UNAVAILABLE/);
    await assert.rejects(report(db,ids[19]),/CONTENT_UNAVAILABLE/);
    await assert.rejects(db.query("update memories set body='forged'"),/permission denied/);
    await assert.rejects(db.query('delete from memories'),/permission denied/);
    await assert.rejects(db.query("select preview_content_report($1,'forged')",[id]),/permission denied/);
    await assert.rejects(db.query("select review_content_report($1,'hide','forged','forged')",[id]),/permission denied/);
    await asUser(db,owner);assert.equal((await db.query('select * from content_reports')).rows.length,0);
    await asUser(db,outsider);await assert.rejects(report(db),/CONTENT_UNAVAILABLE/);
    await db.exec('reset role; set role anon');await assert.rejects(report(db),/permission denied/);
  } finally {await db.close();}
});

test('operator preview contains only this memory and directly scoped photo/audio, not sibling or foreign attachments', async () => {
  const db=await fixture(); try {
    const id=await report(db);
    await db.exec('reset role');
    await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3),($4,$2,$5)',[vault,memory,siblingPath,otherVault,photoPath]);
    const data=await preview(db,id);
    assert.equal(data.available,true);assert.equal(data.fields.Memory,'Reported text');
    assert.deepEqual(data.media.map(m=>m.id).sort(),[photo,audio].sort());
    assert.ok(!JSON.stringify(data).includes('UNREPORTED PRIVATE TEXT'));
    await assert.rejects(db.query("select preview_content_report($1,'QA operator',$2,$3)",[id,siblingPhoto,data.revision]),/MEDIA_UNAVAILABLE/);
    assert.equal((await db.query('select count(*)::int n from content_safety.preview_access')).rows[0].n,1);
    await db.exec('reset role');
    await db.query('update memories set body=$1 where id=$2',['Edited',memory]);
    await db.exec('set role service_role');
    await assert.rejects(db.query("select review_content_report_checked($1,'hide','QA operator','old preview',$2)",[id,data.revision]),/CASE_CHANGED/);
  } finally {await db.close();}
});

test('reviewed hide and restore affect only the memory, its chunks and media including shared-media RPC and Storage reads', async () => {
  const db=await fixture(); try {
    const id=await report(db);
    await decision(db,id,'hide');
    await asUser(db,viewer);
    for (const table of ['memories','memory_photos','memory_chunks']) {
      const key=table==='memories'?'id':'memory_id';
      assert.equal((await db.query(`select * from ${table} where ${key}=$1`,[memory])).rows.length,0,table);
      assert.equal((await db.query(`select * from ${table} where ${key}=$1`,[sibling])).rows.length,1,table);
    }
    assert.equal((await db.query('select * from memory_voice_notes')).rows.length,0);
    assert.deepEqual((await db.query('select id from storage.objects order by id')).rows.map(r=>r.id),[siblingPhoto,legacyPhoto]);
    const bundle=(await db.query('select read_shared_vault_media($1) data',[vault])).rows[0].data;
    assert.equal(bundle.memory_photos.length,1);assert.equal(bundle.memory_photos[0].memory_id,sibling);assert.equal(bundle.memory_voice.length,0);
    await decision(db,id,'restore');await asUser(db,viewer);
    assert.equal((await db.query('select * from memory_photos')).rows.length,2);
    assert.equal((await db.query('select * from storage.objects')).rows.length,4);
    await db.exec('reset role');assert.equal((await db.query('select * from memories')).rows.length,3);
  } finally {await db.close();}
});

test('member blocks still deny personal-memory reports, metadata and Storage', async () => {
  const db=await fixture(); try {
    await db.query('select set_member_block($1,true)',[owner]);
    await assert.rejects(report(db),/CONTENT_UNAVAILABLE/);
    await assert.rejects(db.query('select read_shared_vault_media($1)',[vault]),/access/);
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await db.query('select set_member_block($1,false)',[owner]);
    assert.ok(await report(db));
  } finally {await db.close();}
});

test('members sharing a non-primary family can report, but its scope closes when owner leaves', async () => {
  const db=await fixture(); try {
    await db.exec('reset role');
    await db.query('delete from family_members where user_id=$1',[viewer]);
    await db.query('insert into family_members values($1,$2),($1,$3)',[sharedFamily,viewer,owner]);
    await asUser(db,viewer);const id=await report(db);
    assert.equal((await db.query('select family_id from content_reports')).rows[0].family_id,sharedFamily);
    assert.equal((await preview(db,id)).available,true);
    await db.exec('reset role');await db.query('delete from family_members where user_id=$1 and family_id=$2',[owner,sharedFamily]);
    const data=await preview(db,id);assert.equal(data.available,false);assert.deepEqual(data.media,[]);
    await asUser(db,viewer);await assert.rejects(report(db),/CONTENT_UNAVAILABLE/);
  } finally {await db.close();}
});

test('deleted or moved personal targets do not open new account or family content', async () => {
  const db=await fixture(); try {
    const id=await report(db);
    await db.exec('reset role');await db.query('update memories set vault_id=$1 where id=$2',[otherVault,memory]);
    assert.equal((await preview(db,id)).available,false);
    await db.exec('reset role');await db.query('delete from memories where id=$1',[memory]);
    const data=await preview(db,id);assert.equal(data.available,false);assert.deepEqual(data.media,[]);
  } finally {await db.close();}
});

test('existing legacy-memory and whole-vault reports keep their different review scopes', async () => {
  const db=await fixture(); try {
    let id=await report(db,legacyMemory,null,'legacy_memory');
    let data=await preview(db,id);assert.equal(data.fields.Memory,'Shared legacy text');assert.equal(data.media[0].id,legacyPhoto);
    await asUser(db,viewer);id=await report(db,vault,null,'vault');
    data=await preview(db,id);assert.deepEqual(data.fields,{Name:'Owner'});assert.deepEqual(data.media,[]);
  } finally {await db.close();}
});

test('personal reports keep the ten-per-hour limit', async () => {
  const db=await fixture(); try {
    for(let i=0;i<10;i++) {
      const id=await report(db);
      await decision(db,id,'dismiss');await asUser(db,viewer);
    }
    await assert.rejects(report(db),/REPORT_LIMIT/);
  } finally {await db.close();}
});
