import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { publicationFixture, publicationSql, asUser, dispatched, approve } from './helpers/publication_fixture.mjs';
import { owner, viewer, family, vault, legacy, memory, sibling, legacyMemory, photoPath, legacyPath,
  ids, report, act, finish as retire } from './helpers/retirement_fixture.mjs';
import { consent, finish, request, claim, sharingFixture } from './helpers/screening_fixture.mjs';

async function fixture(t, options) {
  const db = await publicationFixture(undefined, options); t.after(() => db.close()); return db;
}
const visible = async (db, user = viewer, id = memory, table = 'memories') =>
  (await asUser(db, user, `select id from ${table} where id=$1`, [id])).rows.length === 1;
const objectVisible = async (db, path = photoPath, user = viewer) =>
  (await asUser(db, user, 'select id from storage.objects where name=$1', [path])).rows.length === 1;
const origin = async db => (await db.query('select * from content_safety.screening_origins where memory_id=$1', [memory])).rows[0];

test('default-off publication leaves existing reads and writes unchanged', async t => {
  const db = await fixture(t, { enforce: false });
  assert.equal(await visible(db), true); assert.equal(await objectVisible(db), true);
  assert.equal((await db.query('select enforce_publication from content_safety.screening_controls')).rows[0].enforce_publication, false);
  assert.equal(await claim(db), null);
});

test('enforcement cannot be enabled without server capture configured', async t => {
  const db = await fixture(t,{ enabled:false,enforce:false });
  await assert.rejects(db.exec('update content_safety.screening_controls set enforce_publication=true'),/screening_capture_required/);
});

test('enforcement excludes archives but withholds new personal and legacy sources from relatives', async t => {
  const archived = await fixture(t, { fresh: false });
  assert.equal(await visible(archived), true); assert.equal(await objectVisible(archived), true);
  const db = await fixture(t);
  for (const [id, table] of [[memory,'memories'],[legacyMemory,'legacy_memories']]) {
    assert.equal(await visible(db, viewer, id, table), false);
    assert.equal(await visible(db, owner, id, table), true);
  }
  for (const table of ['memory_photos','memory_chunks','legacy_memory_photos','legacy_memory_chunks']) {
    assert.equal((await asUser(db, viewer, `select * from ${table}`)).rows.length, 0);
    assert.ok((await asUser(db, owner, `select * from ${table}`)).rows.length > 0);
  }
  assert.equal(await objectVisible(db), false); assert.equal(await objectVisible(db, legacyPath), false);
  assert.equal(await objectVisible(db, photoPath, owner), true);
  const media = (await asUser(db, viewer, 'select read_shared_vault_media($1) value', [vault])).rows[0].value;
  assert.deepEqual(media.memory_photos, []); assert.deepEqual(media.memory_voice, []);
});

test('owner INSERT RETURNING and subsequent editing still work under the new ceiling', async t => {
  const db = await fixture(t);
  const result = await asUser(db, owner, "insert into memories(id,vault_id,body) values($1,$2,'New') returning id", [ids[18],vault]);
  assert.equal(result.rows[0].id, ids[18]);
  assert.equal(await visible(db, viewer, ids[18]), false);
  assert.equal((await asUser(db, owner, "update memories set body='Edited' where id=$1 returning id", [ids[18]])).rows.length, 1);
  await assert.rejects(asUser(db, viewer, "insert into memories(id,vault_id,body) values($1,$2,'Denied') returning id", [ids[19],vault]), /row-level security/);
});

test('only a current dispatched clear result publishes the exact source and attachments', async t => {
  const db = await fixture(t);
  const job = await dispatched(db);
  assert.equal(await visible(db), false);
  assert.equal((await finish(db, job)).state, 'clear');
  assert.equal(await visible(db), true); assert.equal(await objectVisible(db), true);
  assert.equal(await visible(db, viewer, sibling), false);
  assert.equal(await visible(db, viewer, legacyMemory, 'legacy_memories'), false);
  assert.equal((await asUser(db, viewer, 'select * from memory_chunks')).rows.length, 1);
  assert.equal((await asUser(db, viewer, 'select read_shared_vault_media($1) value', [vault])).rows[0].value.memory_photos.length, 1);
  assert.equal((await finish(db, job, 'review')).code, 'LEASE_UNAVAILABLE');
  assert.equal(await visible(db), true);
});

test('review, provider failure, exhausted budgets and withdrawn permission never publish', async t => {
  for (const scenario of ['review','pending','withdraw','budget','unsupported']) await t.test(scenario, async t => {
    const db = await fixture(t);
    if (scenario === 'budget') {
      await db.exec('update content_safety.screening_controls set max_pending=1');
      assert.equal((await request(db,'memory',sibling)).code,'QUEUED');
      assert.equal((await request(db)).code, 'QUEUE_LIMIT');
    } else if (scenario === 'unsupported') {
      await db.query("insert into memory_voice_notes(memory_id,vault_id,path) values($1,$2,'qa-voice')", [memory,vault]);
      assert.equal((await request(db)).code, 'VOICE_REVIEW_REQUIRED');
    } else {
      const job = await dispatched(db);
      if (scenario === 'withdraw') await consent(db, owner, false);
      await finish(db, job, scenario === 'withdraw' ? 'clear' : scenario);
    }
    assert.equal(await visible(db), false); assert.equal(await objectVisible(db), false);
  });
});

test('approved content remains shared when processing pauses or provider permission is withdrawn', async t => {
  const db = await fixture(t); await approve(db);
  await consent(db, owner, false);
  await db.exec('update content_safety.screening_controls set enabled=false');
  assert.equal(await visible(db), true); assert.equal(await objectVisible(db), true);
  assert.equal(await visible(db, viewer, sibling), false);
});

test('edits, replacement bytes, reference removal and scope changes invalidate approval', async t => {
  for (const scenario of ['text','bytes','reference','scope','date','private']) await t.test(scenario, async t => {
    const db = await fixture(t); await approve(db); const before = await origin(db);
    if (scenario === 'text') await db.query("update memories set body='Changed' where id=$1", [memory]);
    if (scenario === 'bytes') await db.query(`update storage.objects set metadata=jsonb_set(metadata,'{eTag}','"changed"') where name=$1`, [photoPath]);
    if (scenario === 'reference') await db.query('delete from memory_photos where memory_id=$1', [memory]);
    if (scenario === 'scope') await db.query('update memories set vault_id=$1 where id=$2', [ids[18],memory]);
    if (scenario === 'date') await db.query("update memories set created_at=now()+interval '1 year' where id=$1", [memory]);
    if (scenario === 'private') await db.query('update memories set share_to_family_feed=false where id=$1', [memory]);
    assert.notEqual((await origin(db)).id, before.id);
    assert.equal((await origin(db)).cleared_generation, null);
    assert.equal(await visible(db), false); assert.equal(await objectVisible(db), false);
  });
});

test('editing and reverting cannot accept an in-flight old result or restore an old approval', async t => {
  const db = await fixture(t); const job = await dispatched(db);
  await db.query("update memories set body='Changed' where id=$1", [memory]);
  await db.query("update memories set body='Reported' where id=$1", [memory]);
  assert.equal((await finish(db, job)).state, 'stale'); assert.equal(await visible(db), false);
  await approve(db); assert.equal(await visible(db), true);
});

test('new unattached upload and removed source never become family-readable through old folder access', async t => {
  const db = await fixture(t);
  const newPath = `${owner}/${vault}/memories/${memory}/new.png`;
  await db.query('insert into storage.objects(bucket_id,name,owner,owner_id) values($1,$2,$3::uuid,$3)', ['memory_photos',newPath,owner]);
  assert.equal(await objectVisible(db, newPath), false); assert.equal(await objectVisible(db, newPath, owner), true);
  await approve(db); assert.equal(await objectVisible(db, newPath), false);
  await db.query('delete from memory_photos where memory_id=$1', [memory]);
  await db.query('delete from memories where id=$1', [memory]);
  assert.equal(await objectVisible(db), false); assert.equal(await objectVisible(db, newPath), false);
});

test('report hide and same-byte retirement preserve approval without bypassing restrictions', async t => {
  const db = await fixture(t); await approve(db); const generation = (await origin(db)).id;
  const id = await report(db); await act(db,id,'hide');
  assert.equal(await visible(db), false); assert.equal(await objectVisible(db), false);
  await retire(db,id);
  assert.equal((await origin(db)).id,generation);
  await act(db,id,'restore');
  const path = (await db.query('select path from memory_photos where memory_id=$1', [memory])).rows[0].path;
  assert.equal(await visible(db),true); assert.equal(await objectVisible(db,path),true);
  assert.equal(await objectVisible(db),false);
});

test('approved legacy text and exact same-byte media preservation survive account deletion', async t => {
  const db = await fixture(t); await approve(db,'legacy_memory',legacyMemory);
  const old = (await db.query('select * from content_safety.screening_origins where legacy_memory_id=$1',[legacyMemory])).rows[0];
  await db.query('select claim_account_deletion($1,$2)', [owner,ids[15]]);
  const files = (await db.query('select * from account_deletion_files where target_path is not null')).rows;
  for (const f of files) await db.query(`insert into storage.objects(bucket_id,name,metadata)
    select bucket_id,$1,metadata from storage.objects where bucket_id=$2 and name=$3`, [f.target_path,f.bucket_id,f.source_path]);
  await db.query('select finalize_account_deletion_data($1,$2)', [owner,ids[15]]);
  await db.query('delete from auth.users where id=$1', [owner]);
  assert.equal(await visible(db,viewer,legacyMemory,'legacy_memories'),true);
  const retained = (await db.query('select path from legacy_memory_photos where legacy_memory_id=$1', [legacyMemory])).rows[0].path;
  assert.notEqual(retained,legacyPath); assert.equal(await objectVisible(db,retained),true);
  assert.equal((await db.query('select id from content_safety.screening_origins where legacy_memory_id=$1',[legacyMemory])).rows[0].id,old.id);
});

test('clients cannot forge approval, bypass maintenance or call worker finish', async t => {
  const db = await fixture(t);
  for (const sql of [
    'update content_safety.screening_origins set cleared_generation=id',
    'update content_safety.screening_controls set enforce_publication=false',
    'delete from content_safety.screening_objects',
    `select content_safety.invalidate_screening('memory','${memory}')`,
    `select finish_content_screening('${ids[18]}','${ids[19]}','clear')`,
  ]) await assert.rejects(asUser(db,owner,sql),/permission denied/);
  await approve(db); await db.exec(`insert into member_blocks values('${viewer}','${owner}',now())`);
  assert.equal(await visible(db),false); assert.equal(await objectVisible(db),false);
});

test('parent ownership and family changes invalidate publication, but labels do not', async t => {
  const db = await fixture(t); await approve(db);
  await db.query("update vaults set name='New label' where id=$1", [vault]);
  assert.equal(await visible(db),true);
  await db.query('update vaults set family_id=$1 where id=$2', [ids[18],vault]);
  assert.equal(await visible(db),false);
  await approve(db,'legacy_memory',legacyMemory);
  await db.query('update legacy_family_members set family_id=$1 where id=$2', [ids[18],legacy]);
  assert.equal(await visible(db,viewer,legacyMemory,'legacy_memories'),false);
});

test('bucket collisions cannot invalidate unrelated approved images', async t => {
  const db = await fixture(t); await approve(db); const before = await origin(db);
  await db.query("insert into storage.objects(bucket_id,name) values('unrelated_bucket',$1)", [photoPath]);
  assert.equal((await origin(db)).id,before.id); assert.equal(await visible(db),true);
});

test('client overwrites and delete/recreate cannot reuse an enrolled media address', async t => {
  const db = await fixture(t); await approve(db);
  await db.exec('create policy fixture_update on storage.objects for update to authenticated using(true) with check(true)');
  assert.equal((await asUser(db,owner,`update storage.objects set metadata=jsonb_set(metadata,'{eTag}','"changed"') where name=$1 returning id`,[photoPath])).rows.length,0);
  assert.equal(await visible(db),true);
  await db.query('delete from storage.objects where name=$1',[photoPath]);
  assert.equal(await visible(db),false);
  await assert.rejects(db.query('insert into storage.objects(bucket_id,name,owner,owner_id) values($1,$2,$3::uuid,$3)',
    ['vault_photos',photoPath,owner]),/SCREENING_MEDIA_ADDRESS_USED/);
  assert.equal((await db.query('select object_id from content_safety.screening_objects where path=$1',[photoPath])).rows[0].object_id,null);
});

test('relinking a tracked upload to an excluded archive does not confer family access', async t => {
  const db = await fixture(t, { fresh:false });
  const path = `${owner}/${vault}/memories/${memory}/new-archive-photo.png`;
  await db.query('insert into storage.objects(bucket_id,name,owner,owner_id) values($1,$2,$3::uuid,$3)', ['memory_photos',path,owner]);
  await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)', [vault,memory,path]);
  assert.equal(await visible(db),true); assert.equal(await objectVisible(db),true);
  assert.equal(await objectVisible(db,path),false); assert.equal(await objectVisible(db,path,owner),true);
});

test('attachment registration, invalid copies and id reuse cannot inherit earlier approval', async t => {
  const db = await fixture(t); await approve(db);
  await db.query('delete from memory_photos where memory_id=$1',[memory]);
  await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,photoPath]);
  assert.equal(await visible(db),false);
  await approve(db);
  await db.query('delete from memories where id=$1',[memory]);
  await db.query("insert into memories(id,vault_id,body) values($1,$2,'Reported')",[memory,vault]);
  assert.equal(await visible(db),false); assert.equal(await objectVisible(db),false);
});

test('catalog audit detects only known historical fixture grants, not new privileged exposure', async t => {
  const db = await fixture(t);
  const audit = await readFile(new URL('../verification/launch_access_audit.sql',import.meta.url),'utf8');
  const checks = (await db.query(audit)).rows;
  assert.deepEqual(checks.find(r=>r.check_name==='unexpected_client_privileged_functions').findings,
    ['everroot_assert_legacy_avatar_storage_capacity()','everroot_assert_storage_object_capacity()']);
  assert.deepEqual(checks.find(r=>r.check_name==='private_review_relations_accessible').findings,[]);
  assert.equal((await db.query("select relrowsecurity from pg_class where oid='content_safety.screening_objects'::regclass")).rows[0].relrowsecurity,true);
});

test('migration keeps existing policy definitions, payment/quota/deletion routines and stored bytes unchanged', async t => {
  const db = await sharingFixture(); t.after(()=>db.close());
  const functions = (await db.query(`select p.oid,pg_get_functiondef(p.oid) body from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','content_safety') and p.prokind='f'
      and p.oid not in ('content_safety.memory_visible(uuid)'::regprocedure,'content_safety.legacy_memory_visible(uuid)'::regprocedure,
        'public.finish_content_screening(uuid,uuid,text)'::regprocedure) order by p.oid`)).rows;
  const policies = (await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows;
  const objects = (await db.query('select * from storage.objects order by id')).rows;
  await db.exec(publicationSql);
  for(const f of functions) assert.equal((await db.query('select pg_get_functiondef($1) body',[f.oid])).rows[0].body,f.body);
  const after = (await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows;
  for(const p of policies) assert.deepEqual(after.find(r=>r.schemaname===p.schemaname && r.tablename===p.tablename && r.policyname===p.policyname),p);
  assert.deepEqual((await db.query('select * from storage.objects order by id')).rows,objects);
  assert.equal(after.filter(p=>!policies.some(old=>old.schemaname===p.schemaname && old.tablename===p.tablename && old.policyname===p.policyname))
    .every(p=>p.permissive==='RESTRICTIVE'),true);
});
