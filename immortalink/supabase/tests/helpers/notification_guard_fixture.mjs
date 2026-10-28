import { readFile } from 'node:fs/promises';
export const notificationMigration=await readFile(new URL('../../migrations/20261026072757_guard_family_notification_dispatch.sql',import.meta.url),'utf8');
export const ids=Array.from({length:12},(_,i)=>`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
export const [actor,recipient,other,family,vault,memory,outsider]=ids;
export async function notificationFixture(db,{roles=true}={}) {
  await db.exec(`
    ${roles?'create role anon; create role authenticated; create role service_role;':''}
    create schema auth;
    create schema content_safety;
    create table auth.users(id uuid primary key);
    create table family_groups(id uuid primary key);
    create table family_members(family_id uuid,user_id uuid,joined_at timestamptz default now(),primary key(family_id,user_id));
    create table vaults(id uuid primary key,family_id uuid,owner_id uuid);
    create table memories(id uuid primary key,vault_id uuid,created_at timestamptz default now(),share_to_family_feed boolean default true);
    create table account_deletion_jobs(user_id uuid primary key);
    create table member_blocks(blocker_id uuid,blocked_id uuid);
    create table family_feed_hidden_vaults(user_id uuid,hidden_vault_id uuid);
    create table content_safety.restrictions(target_kind text,target_id uuid);
    create function content_safety.media_lifecycle_lock() returns void language sql as
      $$select pg_advisory_xact_lock(987654321)$$;
    insert into auth.users values('${actor}'),('${recipient}'),('${other}'),('${outsider}');
    insert into family_groups values('${family}');
    insert into family_members(family_id,user_id) values('${family}','${actor}'),('${family}','${recipient}'),('${family}','${other}');
    insert into vaults values('${vault}','${family}','${actor}');
    insert into memories(id,vault_id) values('${memory}','${vault}');
  `);
  await db.exec(notificationMigration);
}
export async function claim(db,{type='memory_added',target=memory,user=actor}={}) {
  return (await db.query('select public.claim_family_notification($1,$2,$3) as result',[type,target,user])).rows[0].result;
}
