import {readFile} from 'node:fs/promises';
export const actor='00000000-0000-4000-8000-000000000001',vault='00000000-0000-4000-8000-000000000002',memory='00000000-0000-4000-8000-000000000003';
export const textMigration=await readFile(new URL('../../migrations/20261105141230_launch_text_and_index_bounds.sql',import.meta.url),'utf8');
export const budgetMigration=await readFile(new URL('../../migrations/20261105142822_launch_global_ai_budget.sql',import.meta.url),'utf8');
export async function setup(db) {
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz);
 create schema heiro_business; create function heiro_business.require_owner() returns uuid language plpgsql as $$begin raise exception 'BUSINESS_ACCESS_DENIED';end$$;
 create table public.memories(id uuid primary key,vault_id uuid,body text,prompt_text text,memory_date_label text,people text,location text,mood text);
 create table public.memory_voice_notes(id uuid primary key default gen_random_uuid(),vault_id uuid,memory_id uuid,title text,transcript text,created_at timestamptz default now());
 create table public.memory_chunks(id uuid primary key default gen_random_uuid(),vault_id uuid,memory_id uuid,chunk_index int,chunk_text text);
 create table public.legacy_memories(id uuid,body text,prompt_text text);
 create table public.vaults(id uuid,about_me_text text,name text);
 create table public.legacy_family_members(id uuid,about_me_text text,name text);
 create table public.legacy_memory_voice_notes(id uuid,title text,transcript text);
 insert into auth.users(id) values('${actor}');
 insert into memories(id,vault_id,body,prompt_text) values('${memory}','${vault}','Saved original story','Title');`);
 await db.exec(textMigration);await db.exec(budgetMigration);
}
export const index=db=>db.query('select rebuild_memory_index($1,$2,$3) result',[actor,vault,memory]);
