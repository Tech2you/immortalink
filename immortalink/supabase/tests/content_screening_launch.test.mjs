import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { reviewFixture, queue, preview } from './helpers/screening_review_fixture.mjs';
import { request, claim, prepare, claimPhoto, finishPhoto, finish } from './helpers/screening_fixture.mjs';
import { owner, viewer, vault, memory, photoPath, audioPath } from './helpers/retirement_fixture.mjs';
import { asUser } from './helpers/publication_fixture.mjs';

const sql = await readFile(new URL('../migrations/20261105172337_content_screening_launch_compatibility.sql', import.meta.url), 'utf8');
const editSql = await readFile(new URL('../migrations/20261105180100_content_screening_material_edits.sql', import.meta.url), 'utf8');
const imageSql = await readFile(new URL('../migrations/20261105195157_content_screening_single_image_requests.sql', import.meta.url), 'utf8');
async function fixture(t) {
  const db = await reviewFixture(); t.after(() => db.close());
  await db.exec(sql); await db.exec(editSql); await db.exec(imageSql);
  await db.exec('create or replace function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1073741824::bigint$$');
  await permission(db, true);
  return db;
}
const permission = (db, value) => asUser(db, owner,
  'select set_content_screening_permission($1,$2,$3)', [value, 'openai-safety-text-photo-2026-11-05', owner]);
async function photos(db, count) {
  for (let i = 1; i < count; i++) {
    const path = photoPath.replace('photo.png', `photo-${i}.jpg`);
    await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)', [vault, memory, path]);
    await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) select bucket_id,$1,owner,owner_id,metadata from storage.objects where name=$2', [path, photoPath]);
  }
}
const voice = db => db.query('insert into memory_voice_notes(vault_id,memory_id,path) values($1,$2,$3)', [vault, memory, audioPath]);

test('20 photos plus a recording still check all 20 photos, and a flag remains reviewable', async t => {
  const db = await fixture(t); await photos(db, 20); await voice(db);
  assert.equal((await request(db)).state, 'queued');
  const job = await claim(db), source = await prepare(db, job);
  assert.equal(source.images.length, 20); assert.equal(source.report_only, false);
  assert(!JSON.stringify(source.images).includes('.m4a'));
  assert.equal((await prepare(db, job, true)).code, 'PHOTOS_NOT_READY');
  for (let i = 0; i < 20; i++) {
    const ticket = await claimPhoto(db, job, i);
    assert.equal(ticket.code, 'PHOTO_CLAIMED');
    assert.equal((await finishPhoto(db, ticket.ticket_id, 524289)).code, 'PHOTO_INVALID');
    assert.equal((await finishPhoto(db, ticket.ticket_id, 524288)).code, 'PHOTO_READY');
  }
  assert.equal((await claimPhoto(db, job, 20)).code, 'PHOTO_UNAVAILABLE');
  assert.equal((await prepare(db, job, true)).requests_reserved, 20);
  assert.equal((await db.query("select used from content_safety.screening_budgets where scope='global_day'")).rows[0].used, 20);
  assert.equal((await finish(db, job, 'review')).state, 'review');
  const held = await queue(db), detail = await preview(db, held[0].id);
  assert.equal(detail.available, true); assert.equal(detail.media.length, 20);
  assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 0);
});

test('a long Unicode story reserves every request before any provider work', async t => {
  const db = await fixture(t);
  await db.exec('delete from memory_photos');
  await db.query('update memories set body=$1 where id=$2', ['🙂'.repeat(50000), memory]);
  assert.equal((await request(db)).state, 'queued');
  const job = await claim(db), source = await prepare(db, job);
  assert.equal(source.code, 'READY');
  const expected = Math.ceil(Array.from(source.text).length / 4000);
  const result = await prepare(db, job, true);
  assert.equal(result.requests_reserved, expected);
  assert.equal((await db.query("select used from content_safety.screening_budgets where scope='global_day'")).rows[0].used, expected);
  assert.equal((await prepare(db, job, true)).code, 'LEASE_UNAVAILABLE');
});

test('recording-only sharing sends no provider work and does not require OpenAI permission', async t => {
  const db = await fixture(t); await permission(db, false);
  await db.query('delete from memory_photos where memory_id=$1', [memory]);
  await db.query("update memories set body='',prompt_text='' where id=$1", [memory]);
  await voice(db);
  const status = (await asUser(db, owner, 'select get_content_sharing_status($1,$2,$3) value', ['memory', memory, owner])).rows[0].value;
  assert.equal(status.state, 'ready_no_check');
  assert.equal((await request(db)).state, 'queued');
  const job = await claim(db), source = await prepare(db, job);
  assert.equal(source.report_only, true); assert.deepEqual(source.images, []);
  assert.equal((await prepare(db, job, true)).requests_reserved, 0);
  assert.equal((await finish(db, job)).state, 'clear');
  assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 1);
});

test('appending a recording never bypasses consent for the written story or photos', async t => {
  const db = await fixture(t); await permission(db, false); await voice(db);
  assert.equal((await request(db)).code, 'PERMISSION_REQUIRED');
  assert.equal(await claim(db), null);
});

test('21 photos and a stale disclosure cannot authorize a check', async t => {
  const db = await fixture(t); await photos(db, 21);
  assert.equal((await request(db)).code, 'ATTACHMENT_LIMIT');
  await assert.rejects(asUser(db, owner, 'select set_content_screening_permission(true,$1,$2)',
    ['openai-safety-text-photo-2026-10-23', owner]), /disclosure changed/);
});

test('untouched archives remain readable; editing text requires a fresh sharing request', async t => {
  const db = await reviewFixture(undefined, { fresh: false }); t.after(() => db.close());
  await db.exec(sql); await db.exec(editSql); await db.exec(imageSql); await permission(db, true);
  assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 1);
  await db.exec('alter table memories add column updated_at timestamptz');
  await db.query('update memories set updated_at=clock_timestamp() where id=$1', [memory]);
  assert.equal((await db.query('select * from content_safety.screening_origins where memory_id=$1',[memory])).rows.length,0);
  await db.query('update memories set body=$1 where id=$2', ['New story', memory]);
  assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 0);
  assert.equal((await asUser(db, owner, 'select id from memories where id=$1', [memory])).rows.length, 1);
  assert.equal(await claim(db), null);
  assert.equal((await request(db)).state, 'queued');
});

test('adding a photo enrolls an old memory and a withdrawn permission cannot be bypassed', async t => {
  const db = await reviewFixture(undefined, { fresh: false }); t.after(() => db.close());
  await db.exec(sql); await db.exec(editSql); await db.exec(imageSql); await permission(db, false);
  await photos(db, 2);
  assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 0);
  assert.equal((await request(db)).code, 'PERMISSION_REQUIRED');
  assert.equal(await claim(db),null);
});
