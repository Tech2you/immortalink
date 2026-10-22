// PGLITE_MODULE points to an isolated installation of @electric-sql/pglite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20260928212919_family_owner_successor.sql', import.meta.url), 'utf8');
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const c = '00000000-0000-4000-8000-000000000003';
const f = '00000000-0000-4000-8000-000000000004';
async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create table family_groups(id uuid primary key, created_by uuid);
    create table family_members(family_id uuid, user_id uuid, role text, joined_at timestamptz,
      primary key(family_id,user_id));
    create table vaults(id uuid, owner_id uuid, display_name text, name text, created_at timestamptz);
    create table legacy_family_members(family_id uuid, created_by uuid);
    create table family_entitlements(family_id uuid, billing_owner_user_id uuid);
    insert into auth.users values ('${a}'),('${b}'),('${c}');
    insert into family_groups values ('${f}','${a}');
    insert into family_members values ('${f}','${a}','owner',now()-interval '3 days'),
      ('${f}','${b}','member',now()-interval '2 days'),('${f}','${c}','member',now());
    insert into family_entitlements values ('${f}','${a}');
    insert into legacy_family_members values ('${f}','${a}');
    select set_config('test.uid','${a}',false);
  `);
  await db.exec(migration);
  return db;
}

test('chosen successor wins; shared authorship transfers but billing does not', async () => {
  const db = await fixture();
  try {
    await db.query('select set_family_account_successor($1,$2)', [f,c]);
    const result = await db.query('select handoff_family_for_account_deletion($1,$2) as id',[f,a]);
    assert.equal(result.rows[0].id,c);
    assert.equal((await db.query('select role from family_members where user_id=$1',[c])).rows[0].role,'owner');
    assert.equal((await db.query('select created_by from legacy_family_members')).rows[0].created_by,c);
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id,a);
  } finally { await db.close(); }
});

test('departed successor falls back to oldest member; last member returns null', async () => {
  const db = await fixture();
  try {
    await db.query('select set_family_account_successor($1,$2)',[f,c]);
    await db.query('delete from family_members where user_id=$1',[c]);
    assert.equal((await db.query('select handoff_family_for_account_deletion($1,$2) as id',[f,a])).rows[0].id,b);
    await db.query('delete from family_members where user_id=$1',[b]);
    assert.equal((await db.query('select handoff_family_for_account_deletion($1,$2) as id',[f,a])).rows[0].id,null);
  } finally { await db.close(); }
});

test('automatic fallback prefers remaining owner over older member', async () => {
  const db = await fixture();
  try {
    await db.query("update family_members set role='owner' where user_id=$1",[c]);
    assert.equal((await db.query('select handoff_family_for_account_deletion($1,$2) as id',[f,a])).rows[0].id,c);
  } finally { await db.close(); }
});

test('nonowners, outsiders and self cannot nominate; internal handoff is not client-callable', async () => {
  const db = await fixture();
  try {
    await assert.rejects(db.query('select set_family_account_successor($1,$2)',[f,a]), /another current/);
    await assert.rejects(db.query('select set_family_account_successor($1,$2)',[f,f]), /another current/);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    await assert.rejects(db.query('select set_family_account_successor($1,$2)',[f,c]), /Only a family owner/);
    await assert.rejects(db.query('select get_family_account_successors($1)',[f]), /Only a family owner/);
    const {rows} = await db.query("select has_function_privilege('authenticated','handoff_family_for_account_deletion(uuid,uuid)','execute') as allowed");
    assert.equal(rows[0].allowed,false);
  } finally { await db.close(); }
});
