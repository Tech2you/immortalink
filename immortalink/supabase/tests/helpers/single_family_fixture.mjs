import { readFile } from 'node:fs/promises';

const readMigration = name => readFile(new URL(`../../migrations/${name}.sql`, import.meta.url), 'utf8');
export const launchGuard = await readMigration('20261025095147_single_family_launch_guard');
const joins = await readMigration('20260826123349_harden_family_invite_acceptance_race');
const cleanup = await readMigration('20260808120000_cleanup_empty_family_groups');
const primary = await readMigration('20260721140000_fix_primary_family_switch');

export const ids = Array.from({ length: 12 }, (_, i) => `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`);
export const [user, ownerA, ownerB, familyA, familyB, vault, legacyUser, legacyVault, familyC] = ids;

// The create RPC predates checked-in migrations. Its body was compared with
// pg_get_functiondef on the live project read-only on 2026-10-25. Both join RPCs,
// leave/cleanup and set_primary_family above use the checked-in definitions.
const createFamily = `
create function public.create_family_group_and_link_vault(p_family_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_family_id uuid := gen_random_uuid();
  v_vault_id uuid;
begin
  if v_me is null then raise exception 'Not authenticated'; end if;
  select id into v_vault_id from public.vaults where owner_id = v_me limit 1;
  if v_vault_id is null then raise exception 'No vault found for your account'; end if;
  insert into public.family_groups (id, name, created_by, created_at)
  values (v_family_id, p_family_name, v_me, now());
  insert into public.family_members (family_id, user_id, role, slot_key)
  values (v_family_id, v_me, 'owner', null)
  on conflict (family_id, user_id) do update set role = excluded.role, slot_key = excluded.slot_key;
  update public.vaults set family_id = v_family_id where id = v_vault_id;
  return v_family_id;
end;
$$;`;

export async function singleFamilyFixture(db, { createRoles = true, grandfathered = false } = {}) {
  await db.exec(`
    ${createRoles ? 'create role anon; create role authenticated; create role service_role;' : ''}
    create schema auth;
    create function auth.uid() returns uuid language sql as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    grant usage on schema auth to authenticated;
    create table family_groups(id uuid primary key, name text, created_by uuid, created_at timestamptz);
    create table family_members(family_id uuid references family_groups on delete cascade,
      user_id uuid, role text, slot_key text, joined_at timestamptz default now(),
      is_primary boolean not null default false, primary key(family_id,user_id));
    create index idx_family_members_user on family_members(user_id);
    create unique index family_members_one_primary_per_user on family_members(user_id) where is_primary;
    create table vaults(id uuid primary key, owner_id uuid, family_id uuid);
    create table family_invites(id uuid default gen_random_uuid(),
      family_id uuid references family_groups on delete cascade, invite_code text,
      slot_key text, created_by uuid, inviter_vault_id uuid, expires_at timestamptz,
      used_at timestamptz, used_by uuid, used_by_vault_id uuid);
    create table family_relationships(family_id uuid, parent_type text, parent_id uuid,
      child_type text, child_id uuid, relationship_kind text);
    create function everroot_assert_can_add_family_member(uuid,uuid)
      returns void language sql as $$ select $$;
  `);
  await db.exec(joins);
  await db.exec(cleanup);
  await db.exec(primary);
  await db.exec(createFamily);
  await db.exec(`
    insert into family_groups values
      ('${familyA}','Family A','${ownerA}',now()),
      ('${familyB}','Family B','${ownerB}',now()),
      ('${familyC}','Empty unclaimed tree','${user}',now());
    insert into family_members(family_id,user_id,role) values
      ('${familyA}','${ownerA}','owner'), ('${familyB}','${ownerB}','owner');
    insert into vaults values('${vault}','${user}',null),('${legacyVault}','${legacyUser}','${familyA}');
    insert into family_invites(family_id,invite_code,slot_key,created_by,expires_at) values
      ('${familyA}','INVITE-A','child_1','${ownerA}',now()+interval '1 day'),
      ('${familyB}','INVITE-B','child_1','${ownerB}',now()+interval '1 day');
    ${grandfathered ? `insert into family_members(family_id,user_id,role,is_primary) values
      ('${familyA}','${legacyUser}','member',true),('${familyB}','${legacyUser}','member',false);` : ''}
    alter table family_members enable row level security;
    create policy own_memberships on family_members for select to authenticated using(user_id=auth.uid());
    grant select on family_members to authenticated;
    grant execute on function public.set_primary_family(uuid) to authenticated;
    select set_config('test.uid','${user}',false);
  `);
  await db.exec(launchGuard);
}

export async function authenticate(db, id = user) {
  await db.query("select set_config('test.uid',$1,false)", [id]);
  await db.exec('set role authenticated');
}
