import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261025183407_allow_family_members_to_rename.sql', import.meta.url), 'utf8');
const owner = '00000000-0000-4000-8000-000000000001';
const member = '00000000-0000-4000-8000-000000000002';
const outsider = '00000000-0000-4000-8000-000000000003';
const family = '00000000-0000-4000-8000-000000000004';
const otherFamily = '00000000-0000-4000-8000-000000000005';

async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$select nullif(current_setting('test.uid', true), '')::uuid$$;
    create table public.family_groups(id uuid primary key, name text, created_by uuid);
    create table public.family_members(family_id uuid, user_id uuid, role text,
      primary key(family_id, user_id));
    create table public.family_entitlements(family_id uuid, billing_owner_user_id uuid, plan text);
    insert into public.family_groups values
      ('${family}', 'Our family', '${owner}'), ('${otherFamily}', 'Other family', '${outsider}');
    insert into public.family_members values
      ('${family}', '${owner}', 'owner'), ('${family}', '${member}', 'member'),
      ('${otherFamily}', '${outsider}', 'owner');
    insert into public.family_entitlements values ('${family}', '${member}', 'family');
    alter table public.family_groups enable row level security;
    alter table public.family_members enable row level security;
  `);
  await db.exec(migration);
  return db;
}

async function rename(db, user, target = family, name = 'New name') {
  await db.query("select set_config('test.uid', $1, false)", [user ?? '']);
  await db.exec('set role authenticated');
  try {
    await db.query('select public.rename_family($1, $2)', [target, name]);
  } finally {
    await db.exec('reset role');
  }
}

for (const [label, user] of [['owner', owner], ['member', member]]) {
  test(`${label} can rename, without changing membership, ownership or billing`, async () => {
    const db = await fixture();
    try {
      const membersBefore = (await db.query('select * from family_members order by user_id')).rows;
      const billingBefore = (await db.query('select * from family_entitlements')).rows;
      await rename(db, user, family, '  Updated family  ');
      assert.deepEqual((await db.query('select * from family_groups where id=$1', [family])).rows,
        [{ id: family, name: 'Updated family', created_by: owner }]);
      assert.deepEqual((await db.query('select * from family_members order by user_id')).rows, membersBefore);
      assert.deepEqual((await db.query('select * from family_entitlements')).rows, billingBefore);
      assert.equal((await db.query('select name from family_groups where id=$1', [otherFamily])).rows[0].name, 'Other family');
    } finally { await db.close(); }
  });
}

test('outsider and unauthenticated caller are denied', async () => {
  const db = await fixture();
  try {
    for (const user of [outsider, null]) {
      await assert.rejects(rename(db, user), (error) => error.code === '42501');
    }
    assert.equal((await db.query('select name from family_groups where id=$1', [family])).rows[0].name, 'Our family');
  } finally { await db.close(); }
});

test('membership in one family cannot rename another or an unknown family', async () => {
  const db = await fixture();
  try {
    await assert.rejects(rename(db, member, otherFamily), (error) => error.code === '42501');
    await assert.rejects(rename(db, member, member), (error) => error.code === '42501');
  } finally { await db.close(); }
});

test('former member is denied even if still the billing sponsor', async () => {
  const db = await fixture();
  try {
    await db.query('delete from family_members where user_id=$1', [member]);
    await assert.rejects(rename(db, member), (error) => error.code === '42501');
  } finally { await db.close(); }
});

test('blank, null and overlong names are rejected without a write', async () => {
  const db = await fixture();
  try {
    for (const name of [null, '', '   ', 'a'.repeat(101)]) {
      await assert.rejects(rename(db, member, family, name), (error) => error.code === '22023');
    }
    assert.equal((await db.query('select name from family_groups where id=$1', [family])).rows[0].name, 'Our family');
    await rename(db, member, family, 'a'.repeat(100));
    assert.equal((await db.query('select length(name) as length from family_groups where id=$1', [family])).rows[0].length, 100);
  } finally { await db.close(); }
});

test('migration is repeatable, RPC stays authenticated-only and direct writes stay denied', async () => {
  const db = await fixture();
  try {
    await db.exec(migration);
    const { rows } = await db.query(`select
      has_function_privilege('anon', 'public.rename_family(uuid,text)', 'execute') as anon,
      has_function_privilege('authenticated', 'public.rename_family(uuid,text)', 'execute') as authenticated,
      has_table_privilege('authenticated', 'public.family_groups', 'update') as direct_update`);
    assert.deepEqual(rows[0], { anon: false, authenticated: true, direct_update: false });
    await rename(db, member);
  } finally { await db.close(); }
});
