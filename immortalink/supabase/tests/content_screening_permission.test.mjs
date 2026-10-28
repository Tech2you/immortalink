import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL(
  '../migrations/20261023110215_content_screening_permission.sql', import.meta.url,
), 'utf8');
const aiMigration = await readFile(new URL(
  '../migrations/20261001215816_ai_processing_consent.sql', import.meta.url,
), 'utf8');
const policy = 'openai-safety-text-photo-2026-10-23';
const alice = '00000000-0000-4000-8000-000000000001';
const bob = '00000000-0000-4000-8000-000000000002';

async function fixture(t) {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema content_safety;
    create table auth.users (id uuid primary key);
    insert into auth.users values ('${alice}'), ('${bob}');
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
    grant usage on schema auth, content_safety to anon, authenticated, service_role;
  `);
  await db.exec(aiMigration);
  await db.exec(migration);
  return db;
}

async function asUser(db, id) {
  await db.exec('reset role; set role authenticated;');
  await db.query("select set_config('test.uid', $1, false)", [id]);
}
async function permission(db) {
  return (await db.query('select get_content_screening_permission() as p')).rows[0].p;
}
async function choose(db, allowed, version = policy, expectedUser = alice) {
  return (await db.query('select set_content_screening_permission($1, $2, $3) as p',
    [allowed, version, expectedUser])).rows[0].p;
}
async function matches(db, user, revision) {
  await db.exec('reset role; set role service_role;');
  return (await db.query(
    'select content_safety.screening_permission_matches($1, $2) as ok',
    [user, revision],
  )).rows[0].ok;
}

test('screening starts off and existing AI permission cannot enable it', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  assert.deepEqual(await permission(db), { policy_version: policy, allowed: false, revision: '0' });
  await db.query('select set_ai_processing_consent(true)');
  assert.equal((await permission(db)).allowed, false);
  await choose(db, true);
  await db.query('select set_ai_processing_consent(false)');
  assert.equal((await permission(db)).allowed, true);
  await choose(db, false);
  assert.equal((await db.query('select has_ai_processing_consent() as p')).rows[0].p, false);
});

test('a choice is scoped to the caller and cannot directly grant another account', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  assert.equal((await choose(db, true)).allowed, true);
  await asUser(db, bob);
  assert.deepEqual(await permission(db), { policy_version: policy, allowed: false, revision: '0' });
  await assert.rejects(db.query('select * from content_safety.screening_permissions'), /permission denied/);
  await assert.rejects(db.query(
    'insert into content_safety.screening_permissions(user_id, policy_version, allowed) values ($1, $2, true)',
    [alice, policy],
  ), /permission denied/);
  await assert.rejects(db.query(
    'update content_safety.screening_permissions set allowed = true where user_id = $1', [alice],
  ), /permission denied/);
  await assert.rejects(db.query('select content_safety.screening_permission_matches($1, 1)', [alice]), /permission denied/);
});

test('anonymous and missing-user requests cannot change permission', async (t) => {
  const db = await fixture(t);
  await db.exec('set role anon;');
  await assert.rejects(permission(db), /permission denied/);
  await assert.rejects(choose(db, true), /permission denied/);
  await asUser(db, '');
  await assert.rejects(permission(db), /Not authenticated/);
  await assert.rejects(choose(db, true), /Not authenticated/);
});

test('a delayed choice cannot apply after an account switch, including withdrawal', async (t) => {
  const db = await fixture(t);
  await asUser(db, bob);
  for (const allowed of [true, false]) {
    for (const expected of [alice, null]) {
      await assert.rejects(choose(db, allowed, policy, expected), /Account changed/);
    }
  }
  assert.equal((await permission(db)).revision, '0');
  assert.equal((await choose(db, true, policy, bob)).allowed, true);
  await asUser(db, alice);
  assert.equal((await permission(db)).allowed, false);
});

test('acceptance requires this disclosure but stale clients can always withdraw', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  for (const version of [null, '', 'openai-2026-10-01', 'future-policy']) {
    await assert.rejects(choose(db, true, version), /Screening disclosure changed/);
  }
  await assert.rejects(choose(db, null), /Permission choice required/);
  assert.equal((await permission(db)).revision, '0');
  await choose(db, true);
  assert.equal((await choose(db, false, 'old-policy')).allowed, false);
  assert.equal((await choose(db, false, null)).allowed, false);
});

test('withdrawal and re-acceptance invalidate every previously captured revision', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  const original = await choose(db, true);
  assert.equal(await matches(db, alice, original.revision), true);
  assert.equal(await matches(db, bob, original.revision), false);
  assert.equal(await matches(db, alice, null), false);
  await asUser(db, alice);
  const revoked = await choose(db, false);
  assert.equal(await matches(db, alice, original.revision), false);
  assert.equal(await matches(db, alice, revoked.revision), false);
  await asUser(db, alice);
  const renewed = await choose(db, true);
  assert.equal(renewed.revision, '3');
  assert.equal(await matches(db, alice, original.revision), false);
  assert.equal(await matches(db, alice, renewed.revision), true);
});

test('old policies and deleted accounts fail the worker permission predicate', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  const accepted = await choose(db, true);
  await db.exec('reset role;');
  await db.query('update content_safety.screening_permissions set policy_version = $1', ['old-policy']);
  assert.equal(await matches(db, alice, accepted.revision), false);
  await asUser(db, alice);
  assert.equal((await permission(db)).allowed, false);
  const renewed = await choose(db, true);
  await db.exec('reset role;');
  await db.query('delete from auth.users where id = $1', [alice]);
  assert.equal(await matches(db, alice, renewed.revision), false);
  await db.exec('reset role;');
  assert.equal((await db.query('select count(*)::int as n from content_safety.screening_permissions')).rows[0].n, 0);
  await asUser(db, alice);
  await assert.rejects(choose(db, true), /foreign key constraint/);
});

test('permission revisions remain lossless above the JavaScript integer limit', async (t) => {
  const db = await fixture(t);
  await asUser(db, alice);
  await choose(db, true);
  await db.exec('reset role;');
  await db.query("update content_safety.screening_permissions set revision = '9007199254740992'");
  await asUser(db, alice);
  const next = await choose(db, true);
  assert.equal(next.revision, '9007199254740993');
  assert.equal(await matches(db, alice, next.revision), true);
  assert.equal(await matches(db, alice, '9007199254740992'), false);
});

test('table stays private, function search paths are fixed and no upload hook is added', async (t) => {
  const db = await fixture(t);
  await db.exec('set role service_role;');
  await assert.rejects(db.query('select * from content_safety.screening_permissions'), /permission denied/);
  await assert.rejects(choose(db, true), /permission denied/);
  await db.exec('reset role;');
  const { rows } = await db.query(`
    select c.relrowsecurity as rls,
      has_table_privilege('authenticated', c.oid, 'SELECT') as client_read,
      has_table_privilege('service_role', c.oid, 'UPDATE') as service_write
    from pg_class c where c.oid = 'content_safety.screening_permissions'::regclass
  `);
  assert.deepEqual(rows, [{ rls: true, client_read: false, service_write: false }]);
  const functions = await db.query(`
    select proconfig from pg_proc where proname in
    ('get_content_screening_permission', 'set_content_screening_permission', 'screening_permission_matches')
  `);
  assert.equal(functions.rows.length, 3);
  for (const f of functions.rows) assert.ok(f.proconfig.some(s => /^search_path=(""|)$/.test(s)));
  assert.doesNotMatch(migration, /create\s+trigger|net\.http|cron\.|storage\./i);
});
