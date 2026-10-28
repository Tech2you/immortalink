import { test } from 'node:test';
import assert from 'node:assert/strict';
import { owner, memory, legacyMemory, ids, photoPath, vault } from './helpers/retirement_fixture.mjs';
import { photoFixture, screeningFixture, photoTicketsSql, enqueue, claim, prepare, finish,
  claimPhoto, finishPhoto, consent, clear } from './helpers/screening_fixture.mjs';

async function fixture(t, enabled = true) { const db = await photoFixture(undefined, enabled); t.after(() => db.close()); return db; }
const start = async db => { await enqueue(db); return claim(db); };
const rows = async db => (await db.query('select * from content_safety.screening_photo_tickets order by image_index')).rows;

test('ticket migration changes no working policies, triggers, objects or unrelated function bodies', async t => {
  const db = await screeningFixture(undefined, true, true); t.after(() => db.close());
  const functions = (await db.query(`select p.oid,pg_get_functiondef(p.oid) body from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','content_safety') and p.prokind='f' and p.proname<>'prepare_content_screening' order by p.oid`)).rows;
  const triggers = (await db.query('select oid,pg_get_triggerdef(oid) body from pg_trigger order by oid')).rows;
  const snapshot = async () => (await db.query(`select jsonb_build_object(
    'policies',(select jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname) from pg_policies p),
    'objects',(select jsonb_agg(to_jsonb(o) order by id) from storage.objects o)) value`)).rows[0].value;
  const before = await snapshot(); await db.exec(photoTicketsSql);
  assert.deepEqual(await snapshot(), before);
  for (const trigger of triggers) assert.equal((await db.query('select pg_get_triggerdef($1) body', [trigger.oid])).rows[0].body, trigger.body);
  const added = (await db.query(`select t.oid,t.tgisinternal,c.conname,c.contype,c.conrelid::regclass::text relation
    from pg_trigger t join pg_constraint c on c.oid=t.tgconstraint`)).rows.filter(t => !triggers.some(old => old.oid === t.oid));
  assert.equal(added.length, 4);
  assert(added.every(t => t.tgisinternal && t.contype === 'f' && t.relation === 'content_safety.screening_photo_tickets'));
  for (const f of functions) assert.equal((await db.query('select pg_get_functiondef($1) body', [f.oid])).rows[0].body, f.body);
  assert.doesNotMatch(photoTicketsSql, /create\s+(trigger|policy)|net\.http|cron\.|bytea/i);
});

test('each photo must finish once before dispatch; manifest binds digest, bytes, ordinal and ticket', async t => {
  const db = await fixture(t), job = await start(db);
  assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
  const ticket = await claimPhoto(db, job);
  assert.equal(ticket.code, 'PHOTO_CLAIMED'); assert.equal(ticket.revision, job.revision);
  assert.equal(ticket.processing_reserved, true); assert.equal(ticket.image_index, 0);
  assert.equal((await claimPhoto(db, job)).code, 'PHOTO_ALREADY_CLAIMED');
  assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
  assert.equal((await finishPhoto(db, ticket.ticket_id)).code, 'PHOTO_READY');
  assert.equal((await finishPhoto(db, ticket.ticket_id, 101)).code, 'PHOTO_UNAVAILABLE');
  assert.deepEqual((await prepare(db, job)).prepared_images, [
    { ticket_id: ticket.ticket_id, image_index: 0, bytes: 100, sha256: 'a'.repeat(64) },
  ]);
  assert.equal((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
  assert.equal((await claimPhoto(db, job)).code, 'LEASE_UNAVAILABLE');
  assert.equal((await finish(db, job)).state, 'clear'); assert.equal(await clear(db), true);
  const budgets = (await db.query('select * from content_safety.screening_processing_budgets')).rows;
  assert(budgets.every(b => b.used_jobs === 1 && b.used_images === 1 && b.used_bytes === 10));
  assert(budgets.every(b => b.used_output_bytes >= 2097152 + 2796204));
});

test('four distinct ordinals are required; missing, swapped-source or expired metadata cannot authorize', async t => {
  const db = await fixture(t);
  for (let i = 1; i < 4; i++) {
    const path = photoPath.replace('photo.png', `photo-${i}.png`);
    await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)', [vault, memory, path]);
    await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) select bucket_id,$1,owner,owner_id,metadata from storage.objects where name=$2', [path, photoPath]);
  }
  const job = await start(db), tickets = [];
  for (let i = 0; i < 4; i++) {
    assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
    const ticket = await claimPhoto(db, job, i); tickets.push(ticket);
    assert.equal((await finishPhoto(db, ticket.ticket_id)).code, 'PHOTO_READY');
  }
  assert.equal((await rows(db)).length, 4);
  await db.query('update content_safety.screening_photo_tickets set source_id=$1 where id=$2', [ids[19], tickets[0].ticket_id]);
  assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
  await db.query('update content_safety.screening_photo_tickets set source_id=$1,expires_at=now()-interval \'1 second\' where id=$2', [tickets[0].image.id, tickets[0].ticket_id]);
  assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
});

for (const mutation of ['edit', 'withdraw', 'withdraw-reaccept', 'delete-memory', 'delete-account-job', 'disable', 'hide', 'change-object']) {
  test(`in-flight single-photo result cannot survive ${mutation}`, async t => {
    const db = await fixture(t), job = await start(db), ticket = await claimPhoto(db, job);
    if (mutation === 'edit') await db.query("update memories set body='New content' where id=$1", [memory]);
    if (mutation.startsWith('withdraw')) { await consent(db, owner, false); if (mutation === 'withdraw-reaccept') await consent(db, owner, true); }
    if (mutation === 'delete-memory') await db.query('delete from memories where id=$1', [memory]);
    if (mutation === 'delete-account-job') await db.query('select claim_account_deletion($1,$2)', [owner, ids[15]]);
    if (mutation === 'disable') await db.exec('update content_safety.screening_controls set enabled=false');
    if (mutation === 'hide') await db.query("insert into content_safety.restrictions(target_kind,target_id) values('memory',$1)", [memory]);
    if (mutation === 'change-object') await db.query("update storage.objects set metadata=jsonb_set(metadata,'{eTag}','\"changed\"') where name=$1", [photoPath]);
    assert.notEqual((await finishPhoto(db, ticket.ticket_id)).code, 'PHOTO_READY');
    assert.notEqual((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
    assert.equal(await clear(db), false);
  });
}

test('expired retries spend new budget, replace at most four metadata rows and reject late old responses', async t => {
  const db = await fixture(t), first = await start(db), old = await claimPhoto(db, first);
  await db.exec("update content_safety.screening_jobs set lease_until=now()-interval '1 minute'");
  const second = await claim(db), next = await claimPhoto(db, second);
  assert.notEqual(next.ticket_id, old.ticket_id);
  assert.equal((await rows(db)).length, 1);
  assert.equal((await finishPhoto(db, old.ticket_id)).code, 'PHOTO_UNAVAILABLE');
  assert.equal((await finishPhoto(db, next.ticket_id)).code, 'PHOTO_READY');
  assert((await db.query('select used_jobs,used_images from content_safety.screening_processing_budgets')).rows.every(b => b.used_jobs === 2 && b.used_images === 2));
  await db.query('delete from content_safety.screening_jobs where id=$1', [first.id]);
  assert.deepEqual(await rows(db), []);
});

test('range/type limits, unknown leases, missing permission and exhausted budgets expose no photo', async t => {
  const db = await fixture(t), job = await start(db);
  for (const index of [null, -1, 4]) assert.deepEqual(await claimPhoto(db, job, index), { code: 'PHOTO_UNAVAILABLE' });
  assert.equal((await claimPhoto(db, { ...job, lease_token: ids[19] })).code, 'LEASE_UNAVAILABLE');
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_processing_budgets')).rows[0].n, 0);
  await db.exec("update content_safety.screening_processing_limits set max_output_bytes=1 where scope='global_month'");
  assert.deepEqual(await claimPhoto(db, job), { code: 'PROCESSING_BUDGET_LIMIT' });
  assert.deepEqual(await rows(db), []);
});

test('malformed completion cannot overwrite a claim and text-only jobs need no photo ticket', async t => {
  const db = await fixture(t), job = await start(db), ticket = await claimPhoto(db, job);
  for (const [bytes, sha] of [[0, 'a'.repeat(64)], [2097153, 'a'.repeat(64)], [1, 'secret'], [null, null]]) {
    assert.equal((await finishPhoto(db, ticket.ticket_id, bytes, sha)).code, 'PHOTO_INVALID');
  }
  assert.equal((await rows(db))[0].state, 'processing');
  await db.exec('delete from memory_photos');
  const textJob = await start(db);
  assert.equal((await prepare(db, textJob, true)).code, 'DISPATCH_RESERVED');
});

test('legacy photos use the same exact-revision ticket and budget rules', async t => {
  const db = await fixture(t); await enqueue(db, 'legacy_memory', legacyMemory);
  const job = await claim(db), ticket = await claimPhoto(db, job);
  assert.equal(ticket.code, 'PHOTO_CLAIMED');
  assert.equal((await finishPhoto(db, ticket.ticket_id)).code, 'PHOTO_READY');
  assert.equal((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
});

test('new RPCs are service-only, base authorization stays private and ticket rows hold metadata only', async t => {
  const db = await fixture(t);
  for (const role of ['anon', 'authenticated', 'service_role']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(db.query('select * from content_safety.screening_photo_tickets'), /permission denied/);
    await assert.rejects(db.query('select content_safety.prepare_content_screening(null,null,true)'), /permission denied/);
    if (role !== 'service_role') {
      await assert.rejects(db.query('select claim_content_screening_photo(null,null,0)'), /permission denied/);
      await assert.rejects(db.query('select finish_content_screening_photo(null,1,$1)', ['a'.repeat(64)]), /permission denied/);
    }
    await db.exec('reset role');
  }
  assert.equal((await db.query("select relrowsecurity rls from pg_class where relname='screening_photo_tickets'")).rows[0].rls, true);
  assert.equal((await db.query("select count(*)::int n from information_schema.columns where table_schema='content_safety' and table_name='screening_photo_tickets' and data_type in ('bytea','jsonb')")).rows[0].n, 0);
});
