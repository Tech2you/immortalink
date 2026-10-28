import { test } from 'node:test';
import assert from 'node:assert/strict';
import { singleFamilyFixture, authenticate, user, familyA, familyB, familyC, vault, legacyUser } from './helpers/single_family_fixture.mjs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');

async function fixture(options) {
  const db = new PGlite();
  await singleFamilyFixture(db, options);
  return db;
}
const limit = error => error.message === 'FAMILY_MEMBERSHIP_LIMIT' && error.code === 'P0001';
const memberships = async (db, id = user) => (await db.query(
  'select family_id from family_members where user_id=$1 order by family_id', [id])).rows.map(row => row.family_id);

for (const rpc of ['join_family_by_relationship_invite', 'join_family_by_invite']) {
  test(`${rpc}: a first invite works; a second is atomic and leaves its invite usable`, async () => {
    const db = await fixture();
    try {
      await authenticate(db);
      await db.query(`select ${rpc}('INVITE-A')`);
      assert.deepEqual(await memberships(db), [familyA]);
      await assert.rejects(db.query(`select ${rpc}('INVITE-B')`), limit);
      assert.deepEqual(await memberships(db), [familyA]);
      await db.exec('reset role');
      assert.equal((await db.query('select family_id from vaults where id=$1', [vault])).rows[0].family_id, familyA);
      assert.equal((await db.query("select used_at from family_invites where invite_code='INVITE-B'")).rows[0].used_at, null);
    } finally { await db.close(); }
  });
}

test('first creation succeeds; second creation rolls back the family and leaves home intact', async () => {
  const db = await fixture();
  try {
    await authenticate(db);
    const family = (await db.query("select create_family_group_and_link_vault('First') as id")).rows[0].id;
    await assert.rejects(db.query("select create_family_group_and_link_vault('Second')"), limit);
    assert.deepEqual(await memberships(db), [family]);
    await db.exec('reset role');
    assert.equal((await db.query("select count(*)::int as count from family_groups where name='Second'")).rows[0].count, 0);
    assert.equal((await db.query('select family_id from vaults where id=$1', [vault])).rows[0].family_id, family);
  } finally { await db.close(); }
});

test('grandfathered memberships, home switching and same-family invite updates remain usable', async () => {
  const db = await fixture({ grandfathered: true });
  try {
    await authenticate(db, legacyUser);
    assert.deepEqual(await memberships(db, legacyUser), [familyA, familyB]);
    await db.query('select set_primary_family($1)', [familyB]);
    await db.query("select join_family_by_relationship_invite('INVITE-A')");
    await db.query("select join_family_by_invite('INVITE-B')");
    assert.deepEqual(await memberships(db, legacyUser), [familyA, familyB]);
    await assert.rejects(db.query("select create_family_group_and_link_vault('Third')"), limit);
  } finally { await db.close(); }
});

test('empty personal vault and an unclaimed empty family do not block first join', async () => {
  const db = await fixture();
  try {
    await authenticate(db);
    await db.query("select join_family_by_relationship_invite('INVITE-A')");
    assert.deepEqual(await memberships(db), [familyA]);
  } finally { await db.close(); }
});

test('an empty owned family is preserved; explicitly leaving it permits the first invite', async () => {
  const db = await fixture();
  try {
    await authenticate(db);
    const ownFamily = (await db.query("select create_family_group_and_link_vault('My Family') as id")).rows[0].id;
    await assert.rejects(db.query("select join_family_by_relationship_invite('INVITE-A')"), limit);
    assert.deepEqual(await memberships(db), [ownFamily]);
    await db.query('select leave_family($1)', [ownFamily]);
    assert.deepEqual(await memberships(db), []);
    await db.query("select join_family_by_relationship_invite('INVITE-A')");
    assert.deepEqual(await memberships(db), [familyA]);
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int as count from family_groups where id=$1', [ownFamily])).rows[0].count, 0);
  } finally { await db.close(); }
});

test('direct or multi-row admissions cannot bypass guard; membership identifiers cannot be reassigned', async () => {
  const db = await fixture();
  try {
    await assert.rejects(db.query(`insert into family_members(family_id,user_id,role) values ($1,$3,'member'),($2,$3,'member')`, [familyA, familyB, user]), limit);
    assert.deepEqual(await memberships(db), []);
    await db.query('insert into family_members(family_id,user_id) values($1,$2)', [familyA, user]);
    await assert.rejects(db.query('insert into family_members(family_id,user_id) values($1,$2)', [familyB, user]), limit);
    await assert.rejects(db.query('update family_members set family_id=$1 where user_id=$2', [familyC, user]), limit);
    await db.query("update family_members set role='owner' where user_id=$1", [user]);
    assert.deepEqual(await memberships(db), [familyA]);
  } finally { await db.close(); }
});

test('the helper has no exposed execute privilege and does not grant direct membership writes', async () => {
  const db = await fixture();
  try {
    for (const role of ['anon', 'authenticated', 'service_role']) {
      assert.equal((await db.query("select has_function_privilege($1,'family_access.guard_single_family_admission()','EXECUTE') as allowed", [role])).rows[0].allowed, false);
    }
    await authenticate(db);
    await assert.rejects(db.query('insert into family_members(family_id,user_id) values($1,$2)', [familyA, user]), /permission denied/);
  } finally { await db.close(); }
});
