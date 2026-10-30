import { readFile } from 'node:fs/promises';
import { growthFixture } from './family_growth_fixture.mjs';
import { ownerA, ownerB, user, familyA, familyB } from './single_family_fixture.mjs';

const migration = await readFile(new URL('../../migrations/20261028140702_atomic_family_relationships.sql', import.meta.url), 'utf8');
export const ownerVault = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
export async function relationshipFixture(db, { createRoles = true } = {}) {
    await growthFixture(db, { createRoles });
    await db.exec(`
      create table auth.users(id uuid primary key);
      insert into auth.users values('${ownerA}'),('${ownerB}'),('${user}');
      insert into vaults values('${ownerVault}','${ownerA}','${familyA}');
      insert into vaults values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','${ownerB}','${familyB}');
      alter table family_relationships add id uuid primary key default gen_random_uuid();
      alter table family_relationships add check(not(parent_type=child_type and parent_id=child_id));
      alter table legacy_family_members add slot_key text, add display_name text, add birth_year integer,
        add death_year integer, add created_by uuid, add about_me_text text;
      create table legacy_memories(legacy_member_id uuid,life_stage text,prompt_key text,prompt_text text,body text,family_id uuid);
      alter table family_relationships enable row level security;
      create policy relationship_read on family_relationships for select to authenticated using (
        exists(select 1 from family_members where family_id=family_relationships.family_id and user_id=auth.uid()));
      create policy relationship_insert on family_relationships for insert to authenticated with check (
        exists(select 1 from family_members where family_id=family_relationships.family_id and user_id=auth.uid()));
      grant select,insert,update,delete on family_relationships to authenticated;
    `);
    await db.exec(migration);
}
