import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { growthFixture } from './helpers/family_growth_fixture.mjs';
import { ownerA, familyA, familyB, vault } from './helpers/single_family_fixture.mjs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const read = name => readFile(new URL(`../migrations/${name}.sql`, import.meta.url), 'utf8');
const baseline = await read('20260831122613_restore_family_usage_storage_rpc');
const migration = await read('20261031205918_legacy_profile_usage_counter');
async function run(fn) {
  const db = new PGlite();
  try {
    await growthFixture(db);
    await db.exec(`
      alter table vaults add created_at timestamptz default now();
      create function everroot_period_start() returns date language sql stable as $$ select date_trunc('month',now())::date $$;
      create table everroot_ai_usage_periods(scope_type text,scope_id uuid,period_start date,used_count integer);
      create table everroot_transcription_usage_periods(scope_type text,scope_id uuid,period_start date,used_seconds integer);
    `);
    await db.exec(baseline);
    await db.query("select set_config('test.uid',$1,false)", [ownerA]);
    await fn(db);
  } finally { await db.close(); }
}
async function usage(db, id = familyA) {
  return (await db.query('select get_family_entitlements_and_usage($1) value', [id])).rows[0].value;
}

test('reported usage includes retained profiles and matches the enforced cap', () => run(async db => {
  await db.query('insert into legacy_family_members(family_id) select $1 from generate_series(1,8)', [familyA]);
  await db.query('update legacy_family_members set replaced_by_vault_id=$1 where id=(select id from legacy_family_members limit 1)', [vault]);
  const before = await usage(db);
  assert.equal(before.usage.legacy_people, 7);
  await db.exec(migration);
  const after = await usage(db);
  assert.deepEqual(after, {...before, usage: {...before.usage, legacy_people: 8}});
  await assert.rejects(db.query('insert into legacy_family_members(family_id) values($1)', [familyA]), e => e.detail === 'ERR_EVERROOT_LEGACY_LIMIT');
}));

for (const [plan, cap] of [['free',8], ['everroot_family',100], ['everroot_legacy',250]]) {
  test(`${plan} keeps its ${cap} cap and counts only this family's legacy profiles`, () => run(async db => {
    await db.query('insert into family_entitlements values($1,$2)', [familyA,plan]);
    await db.query('insert into legacy_family_members(family_id) values($1),($2)', [familyA,familyB]);
    await db.exec(migration);
    const result = await usage(db);
    assert.equal(result.limits.legacy_people, cap);
    assert.equal(result.usage.legacy_people, 1);
    assert.equal(result.usage.real_members, 1);
  }));
}

test('report keeps authentication, family authorization and function privileges', () => run(async db => {
  const security = () => db.query("select proacl::text,prosecdef,proconfig from pg_proc where oid='get_family_entitlements_and_usage(uuid)'::regprocedure");
  const before = await security();
  await db.exec(migration);
  assert.deepEqual((await security()).rows, before.rows);
  await db.exec('set role authenticated');
  assert.equal((await usage(db)).usage.legacy_people, 0);
  await assert.rejects(usage(db, familyB), /not a member/);
  await db.query("select set_config('test.uid','',false)");
  await assert.rejects(usage(db), /Not authenticated/);
  await db.exec('reset role; set role anon');
  await assert.rejects(usage(db), /permission denied/);
}));
