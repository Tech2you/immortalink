import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261001214854_lock_family_membership_writes.sql', import.meta.url), 'utf8');
const joins = await readFile(new URL('../migrations/20260826123349_harden_family_invite_acceptance_race.sql', import.meta.url), 'utf8');
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const f = '00000000-0000-4000-8000-000000000003';
const v = '00000000-0000-4000-8000-000000000004';
async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    grant usage on schema auth to authenticated;
    create table family_members(family_id uuid,user_id uuid,role text,slot_key text,
      joined_at timestamptz,is_primary boolean default false,primary key(family_id,user_id));
    create table vaults(id uuid,owner_id uuid,family_id uuid);
    create table family_invites(id uuid default gen_random_uuid(),family_id uuid,
      invite_code text,slot_key text,created_by uuid,inviter_vault_id uuid,
      expires_at timestamptz,used_at timestamptz,used_by uuid,used_by_vault_id uuid);
    create table family_relationships(family_id uuid,parent_type text,parent_id uuid,
      child_type text,child_id uuid,relationship_kind text);
    create function everroot_assert_can_add_family_member(uuid,uuid)
      returns void language sql as $$ select $$;
    create function is_family_member(f uuid,u uuid) returns boolean language sql
      security definer set search_path=public as
      $$select exists(select 1 from family_members where family_id=f and user_id=u)$$;
    alter table family_members enable row level security;
    grant all on family_members to anon,authenticated;
    create policy family_members_select_in_family on family_members for select
      using(is_family_member(family_id,auth.uid()));
    create policy family_members_insert_self on family_members for insert with check(user_id=auth.uid());
    create policy family_members_update_self on family_members for update
      using(user_id=auth.uid()) with check(user_id=auth.uid());
    create policy family_members_delete_self on family_members for delete using(user_id=auth.uid());
    insert into family_members values('${f}','${a}','owner',null,now(),true);
    insert into vaults values('${v}','${b}',null);
    insert into family_invites(family_id,invite_code,slot_key,created_by,expires_at)
      values('${f}','VALID-CODE','child_1','${a}',now()+interval '1 hour');
  `);
  await db.exec(joins);
  await db.exec(migration);
  await db.exec(`select set_config('test.uid','${b}',false); set role authenticated;`);
  return db;
}

test('a family UUID cannot admit an outsider or expose memberships', async () => {
  const db = await fixture();
  try {
    assert.deepEqual((await db.query('select * from family_members')).rows, []);
    await assert.rejects(db.query('insert into family_members(family_id,user_id,role) values($1,$2,$3)', [f,b,'owner']), /permission denied/);
    await assert.rejects(db.query("select join_family_by_relationship_invite('WRONG-CODE')"), /invalid, expired/);
  } finally { await db.close(); }
});

test('real invite RPC admits member and slot; cannot promote, move or delete membership directly', async () => {
  const db = await fixture();
  try {
    await db.query("select join_family_by_relationship_invite('VALID-CODE')");
    const rows = (await db.query('select role,slot_key from family_members where user_id=$1',[b])).rows;
    assert.deepEqual(rows,[{role:'member',slot_key:'child_1'}]);
    await assert.rejects(db.query("update family_members set role='owner' where user_id=$1",[b]), /permission denied/);
    await assert.rejects(db.query('update family_members set family_id=$1 where user_id=$2',[a,b]), /permission denied/);
    await assert.rejects(db.query('delete from family_members where user_id=$1',[b]), /permission denied/);
    await assert.rejects(db.query("select join_family_by_relationship_invite('VALID-CODE')"), /invalid, expired/);
  } finally { await db.close(); }
});

test('legacy invite RPC also retains authorized admission', async () => {
  const db = await fixture();
  try {
    await db.query("select join_family_by_invite('VALID-CODE')");
    assert.equal((await db.query('select role from family_members where user_id=$1',[b])).rows[0].role,'member');
  } finally { await db.close(); }
});
