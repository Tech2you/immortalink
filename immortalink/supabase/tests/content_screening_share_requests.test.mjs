import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { owner, viewer, family, vault, memory, sibling, legacyMemory, ids } from './helpers/retirement_fixture.mjs';
import { sharingFixture, photoFixture, sharingSql, freshTargets, request, consent,
  enqueue, claim, prepare, finish, clear, claimPhoto, finishPhoto } from './helpers/screening_fixture.mjs';

const audit = await readFile(new URL('../verification/launch_access_audit.sql', import.meta.url), 'utf8');
async function fixture(t, options) {
  const db = await sharingFixture(undefined, options);
  t.after(() => db.close());
  return db;
}
async function dispatched(db, kind = 'memory', target = memory, user = owner) {
  assert.equal((await request(db, kind, target, user)).state, 'queued');
  const job = await claim(db);
  const source = await prepare(db, job);
  for (let i = 0; i < source.images.length; i++) {
    const ticket = await claimPhoto(db, job, i);
    assert.equal((await finishPhoto(db, ticket.ticket_id)).code, 'PHOTO_READY');
  }
  assert.equal((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
  return job;
}
const count = async (db, table) => (await db.query(`select count(*)::int n from content_safety.${table}`)).rows[0].n;

test('disabled installation neither enrolls existing rows nor starts work on new inserts', async t => {
  const db = await fixture(t, { enabled: false });
  assert.equal(await count(db, 'screening_origins'), 0);
  assert.equal((await request(db)).code, 'SCREENING_DISABLED');
  await db.exec(`update content_safety.screening_controls set enabled=true,eligible_after=now()-interval '1 day'`);
  assert.equal((await request(db)).code, 'REQUEST_UNAVAILABLE');
  assert.equal((await enqueue(db)).code, 'ARCHIVE_EXCLUDED');
  assert.equal(await claim(db), null);
  assert.equal(await count(db, 'screening_jobs'), 0);
});

test('editing archive dates or feed flags cannot enroll personal or legacy memories', async t => {
  const db = await fixture(t, { fresh: false });
  await db.exec(`update memories set created_at=now()+interval '1 year',share_to_family_feed=false;
    update memories set share_to_family_feed=true;
    update legacy_memories set created_at=now()+interval '1 year',body='Edited archive'`);
  for (const [kind, id] of [['memory', memory], ['legacy_memory', legacyMemory]]) {
    assert.equal((await request(db, kind, id)).code, 'REQUEST_UNAVAILABLE');
    assert.equal((await enqueue(db, kind, id)).code, 'ARCHIVE_EXCLUDED');
  }
  assert.equal(await count(db, 'screening_origins'), 0);
  assert.equal(await count(db, 'screening_jobs'), 0);
});

test('new insertion is server-recorded even with a backdated date, but requires an explicit request', async t => {
  const db = await fixture(t, { fresh: false });
  await db.exec("update memories set created_at=now()-interval '40 years'; update legacy_memories set created_at=now()-interval '40 years'");
  await freshTargets(db);
  assert.equal(await count(db, 'screening_origins'), 3);
  assert.equal(await count(db, 'screening_jobs'), 0);
  assert.equal((await enqueue(db)).code, 'SHARING_REQUEST_REQUIRED');
  assert.equal(await claim(db), null);
  assert.equal((await request(db)).state, 'queued');
  assert.equal((await request(db, 'legacy_memory', legacyMemory)).state, 'queued');
});

test('a future activation cutoff cannot enroll early writes or be bypassed by their dates', async t => {
  const db = await fixture(t, { fresh: false });
  await db.exec("update content_safety.screening_controls set eligible_after=now()+interval '1 day'");
  await freshTargets(db);
  await db.exec("update memories set created_at=now()+interval '2 days'; update content_safety.screening_controls set eligible_after=now()-interval '1 day'");
  assert.equal(await count(db, 'screening_origins'), 0);
  assert.equal((await request(db)).code, 'REQUEST_UNAVAILABLE');
});

test('pausing processing never makes newly inserted content an exempt archive on resume', async t => {
  const db = await fixture(t, { fresh: false });
  await db.exec('update content_safety.screening_controls set enabled=false');
  await freshTargets(db);
  assert.equal(await count(db, 'screening_origins'), 3);
  assert.equal((await request(db)).code, 'SCREENING_DISABLED');
  await db.exec('update content_safety.screening_controls set enabled=true');
  assert.equal((await enqueue(db)).code, 'SHARING_REQUEST_REQUIRED');
  assert.equal(await claim(db), null);
  assert.equal((await request(db)).state, 'queued');
});

test('installing the origin gate invalidates previously leased work without a trusted origin', async t => {
  const db = await photoFixture(); t.after(() => db.close());
  await enqueue(db);
  const job = await claim(db);
  assert.equal((await prepare(db, job)).code, 'READY');
  // Enqueue/claim/prepare have already cached their function references.
  await db.exec(sharingSql);
  assert.equal((await prepare(db, job, true)).code, 'SOURCE_CHANGED');
  assert.equal((await finish(db, job)).code, 'LEASE_UNAVAILABLE');
  assert.equal(await clear(db), false);
  assert.equal(await count(db, 'screening_budgets'), 0);
});

test('legacy contribution retention survives author deletion without creating provider permission', async t => {
  const db = await fixture(t);
  assert.equal((await request(db, 'legacy_memory', legacyMemory)).state, 'queued');
  const before = (await db.query('select body from legacy_memories where id=$1', [legacyMemory])).rows[0];
  await db.query('delete from auth.users where id=$1', [owner]);
  assert.deepEqual((await db.query('select body from legacy_memories where id=$1', [legacyMemory])).rows[0], before);
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_origins where legacy_memory_id=$1', [legacyMemory])).rows[0].n, 1);
  assert.equal(await count(db, 'screening_jobs'), 0);
  assert.equal((await request(db, 'legacy_memory', legacyMemory, viewer)).code, 'REQUEST_UNAVAILABLE');
  assert.equal(await clear(db, 'legacy_memory', legacyMemory), false);
});

test('only an authenticated current owner/contributor can request, and account switches fail', async t => {
  const db = await fixture(t);
  await assert.rejects(request(db, 'memory', memory, null, null), /Account changed/);
  await assert.rejects(request(db, 'memory', memory, viewer, owner), /Account changed/);
  for (const [kind, id, user] of [
    ['memory', memory, viewer], ['memory', memory, ids[12]], ['legacy_memory', legacyMemory, viewer],
    ['memory', ids[18], owner], ['vault', vault, owner],
  ]) assert.equal((await request(db, kind, id, user)).code, 'REQUEST_UNAVAILABLE');
  assert.equal(await count(db, 'screening_jobs'), 0);
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_origins where requested_at is not null')).rows[0].n, 0);
  await db.query('update legacy_memories set last_editor_id=$1', [viewer]);
  await consent(db, viewer, true);
  assert.equal((await request(db, 'legacy_memory', legacyMemory, viewer)).state, 'queued');
});

test('private-draft intent, missing consent, former members and deletion cannot dispatch', async t => {
  for (const scenario of ['private', 'consent', 'former-member', 'deleting', 'deleted-user']) {
    await t.test(scenario, async t => {
      const db = await fixture(t);
      if (scenario === 'private') await db.query('update memories set share_to_family_feed=false where id=$1', [memory]);
      if (scenario === 'consent') await consent(db, owner, false);
      if (scenario === 'former-member') await db.query('delete from family_members where user_id=$1', [owner]);
      if (scenario === 'deleting') await db.query('select claim_account_deletion($1,$2)', [owner, ids[15]]);
      if (scenario === 'deleted-user') await db.query('delete from auth.users where id=$1', [owner]);
      const result = await request(db);
      assert.equal(result.code, scenario === 'consent' ? 'PERMISSION_REQUIRED' : 'REQUEST_UNAVAILABLE');
      assert.equal(await claim(db), null);
      assert.equal(await count(db, 'screening_jobs'), 0);
    });
  }
});

test('repeat sharing requests cannot reset review or change a clear revision for another contributor', async t => {
  const db = await fixture(t);
  await consent(db, viewer, true);
  await db.query('update legacy_memories set last_editor_id=$1', [viewer]);
  const job = await dispatched(db, 'legacy_memory', legacyMemory);
  await finish(db, job, 'review');
  const origin = (await db.query('select * from content_safety.screening_origins order by id')).rows;
  const jobs = (await db.query('select * from content_safety.screening_jobs')).rows;
  const duplicate = await request(db, 'legacy_memory', legacyMemory, viewer);
  assert.equal(duplicate.id, job.id); assert.equal(duplicate.state, 'review');
  assert.deepEqual((await db.query('select * from content_safety.screening_origins order by id')).rows, origin);
  assert.deepEqual((await db.query('select * from content_safety.screening_jobs')).rows, jobs);
  assert.equal(await claim(db), null);
});

test('permission, source and restrictions are still rechecked after an authorized request', async t => {
  for (const scenario of ['withdraw', 'edit', 'hide', 'sexual-report', 'scope-move']) {
    await t.test(scenario, async t => {
      const db = await fixture(t);
      const job = await dispatched(db);
      if (scenario === 'withdraw') await consent(db, owner, false);
      if (scenario === 'edit') await db.query("update memories set body='Changed' where id=$1", [memory]);
      if (scenario === 'hide') await db.query("insert into content_safety.restrictions(target_kind,target_id) values('memory',$1)", [memory]);
      if (scenario === 'sexual-report') await db.query(`insert into content_reports(reporter_id,family_id,target_kind,target_id,reason)
        values($1,$2,'memory',$3,'sexual_content')`, [viewer, family, memory]);
      if (scenario === 'scope-move') {
        await db.query('insert into vaults(id,owner_id,family_id) values($1,$2,$3)', [ids[18], owner, family]);
        await db.query('update memories set vault_id=$1 where id=$2', [ids[18], memory]);
      }
      assert.equal((await finish(db, job)).state, 'stale');
      assert.equal(await clear(db), false);
    });
  }
});

test('deletion cleans only the target origin/job/tickets and ID reuse cannot accept an old result', async t => {
  const db = await fixture(t);
  const old = await dispatched(db);
  await request(db, 'memory', sibling);
  const origins = (await db.query('select * from content_safety.screening_origins where memory_id<>$1 or memory_id is null order by id', [memory])).rows;
  await db.query('delete from memories where id=$1', [memory]);
  assert.equal(await count(db, 'screening_jobs'), 1);
  assert.equal(await count(db, 'screening_photo_tickets'), 0);
  assert.equal((await finish(db, old)).code, 'LEASE_UNAVAILABLE');
  assert.deepEqual((await db.query('select * from content_safety.screening_origins order by id')).rows, origins);
  await db.query("insert into memories(id,vault_id,prompt_text,body) values($1,$2,'QA','Reported')", [memory, vault]);
  assert.equal((await enqueue(db)).code, 'SHARING_REQUEST_REQUIRED');
  const next = await request(db);
  assert.notEqual(next.id, old.id);
  assert.equal((await finish(db, old)).code, 'LEASE_UNAVAILABLE');
  assert.equal(await clear(db), false);
});

test('request path retains queue caps without altering storage or creating unbounded work', async t => {
  const db = await fixture(t);
  const storage = (await db.query('select * from storage.objects order by id')).rows;
  await db.exec('update content_safety.screening_controls set max_pending=1,max_user_pending=1');
  assert.equal((await request(db)).state, 'queued');
  for (let i = 0; i < 3; i++) assert.equal((await request(db, 'memory', sibling)).code, 'QUEUE_LIMIT');
  assert.equal(await count(db, 'screening_jobs'), 1);
  assert.deepEqual((await db.query('select * from storage.objects order by id')).rows, storage);
});

test('new private state cannot be read or forged and only the exact caller RPC is exposed', async t => {
  const db = await fixture(t);
  for (const role of ['anon', 'authenticated', 'service_role']) {
    await db.exec(`set role ${role}`);
    for (const query of [
      'select * from content_safety.screening_origins',
      "update content_safety.screening_origins set requested_at=now()",
      `insert into content_safety.screening_origins(memory_id,scope_id) values('${memory}','${vault}')`,
      'delete from content_safety.screening_origins',
      `select content_safety.screening_snapshot('memory','${memory}','${owner}')`,
    ]) await assert.rejects(db.query(query), /permission denied/);
    if (role !== 'authenticated') await assert.rejects(db.query(`select request_content_screening('memory','${memory}','${owner}')`), /permission denied/);
    await db.exec('reset role');
  }
  assert.equal((await db.query("select relrowsecurity rls from pg_class where oid='content_safety.screening_origins'::regclass")).rows[0].rls, true);
  const checks = (await db.query(audit)).rows;
  // The minimal historical fixture omits the later quota-trigger ACL lockdown.
  // Account for those two known fixture grants, not any new screening endpoint.
  const baseline = ['everroot_assert_legacy_avatar_storage_capacity()', 'everroot_assert_storage_object_capacity()'];
  assert.deepEqual(checks.find(r => r.check_name === 'unexpected_client_privileged_functions').findings, baseline);
  await db.exec('grant execute on function content_safety.screening_snapshot(text,uuid,uuid) to authenticated');
  assert.deepEqual((await db.query(audit)).rows.find(r => r.check_name === 'unexpected_client_privileged_functions').findings,
    ['content_safety.screening_snapshot(text,uuid,uuid)', ...baseline]);
});

test('migration preserves existing policies, storage, payments and function identities', async t => {
  const db = await photoFixture(); t.after(() => db.close());
  const functions = (await db.query(`select p.oid,pg_get_functiondef(p.oid) body from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','content_safety')
    and p.prokind='f' and p.oid<>'content_safety.screening_snapshot(text,uuid,uuid)'::regprocedure order by p.oid`)).rows;
  const snapshotOid = (await db.query("select 'content_safety.screening_snapshot(text,uuid,uuid)'::regprocedure::oid id")).rows[0].id;
  const policies = (await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows;
  const triggers = (await db.query('select oid,pg_get_triggerdef(oid) body from pg_trigger order by oid')).rows;
  const objects = (await db.query('select * from storage.objects order by id')).rows;
  await db.exec(sharingSql);
  assert.equal((await db.query("select 'content_safety.screening_snapshot(text,uuid,uuid)'::regprocedure::oid id")).rows[0].id, snapshotOid);
  for (const f of functions) assert.equal((await db.query('select pg_get_functiondef($1) body', [f.oid])).rows[0].body, f.body);
  for (const tr of triggers) assert.equal((await db.query('select pg_get_triggerdef($1) body', [tr.oid])).rows[0].body, tr.body);
  assert.deepEqual((await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows, policies);
  assert.deepEqual((await db.query('select * from storage.objects order by id')).rows, objects);
  assert.equal(await count(db, 'screening_origins'), 0);
  assert.equal((await enqueue(db)).code, 'ARCHIVE_EXCLUDED');
  assert.doesNotMatch(sharingSql, /net\.http|cron\.|create\s+policy|alter\s+policy/i);
});
