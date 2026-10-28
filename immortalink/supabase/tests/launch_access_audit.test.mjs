import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const audit = await readFile(new URL('../verification/launch_access_audit.sql', import.meta.url), 'utf8');
const screeningPermission = await readFile(new URL(
  '../migrations/20261023110215_content_screening_permission.sql', import.meta.url,
), 'utf8');

async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema content_safety; create schema storage;
    revoke create on schema public from public;
    create table storage.buckets(id text primary key,public boolean default false);
    insert into storage.buckets values('vault_photos',false);
    create table public.memories(id uuid);
    alter table public.memories enable row level security;
    grant select on public.memories to authenticated;
    create table content_safety.preview_access(id uuid);
    alter table content_safety.preview_access enable row level security;
    create function public.list_safety_members() returns integer language sql
      security definer set search_path='' as $$select 1$$;
    revoke all on function public.list_safety_members() from public;
    grant execute on function public.list_safety_members() to authenticated;
    create function public.preview_content_report(uuid) returns integer language sql
      security definer set search_path='' as $$select 1$$;
    revoke all on function public.preview_content_report(uuid) from public;
    grant execute on function public.preview_content_report(uuid) to service_role;
  `);
  return db;
}

async function inspect(db) {
  await db.exec('begin read only');
  try {
    return Object.fromEntries((await db.query(audit)).rows.map(row => [row.check_name,row.findings]));
  } finally {
    await db.exec('rollback');
  }
}

test('audit is read-only, preserves intended access and reports missing contract entries', async () => {
  const db = await fixture();
  try {
    const result = await inspect(db);
    assert.equal(Object.keys(result).length,10);
    for (const [name,findings] of Object.entries(result)) {
      if (name !== 'expected_client_functions_unavailable') assert.deepEqual(findings,[],name);
    }
    assert.equal(result.expected_client_functions_unavailable.length,50);
    assert(!result.expected_client_functions_unavailable.includes('public.list_safety_members()'));
    assert.equal((await db.query("select has_function_privilege('authenticated','public.list_safety_members()','EXECUTE') allowed")).rows[0].allowed,true);
  } finally { await db.close(); }
});

test('planned screening contract accepts only the account-bound RPCs, not old overloads or worker grants', async () => {
  const db = await fixture();
  try {
    await db.exec(`
      create schema auth;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql as $$select null::uuid$$;
    `);
    await db.exec(screeningPermission);
    let result = await inspect(db);
    assert.deepEqual(result.unexpected_client_privileged_functions, []);
    assert.deepEqual(result.anonymous_privileged_functions, []);
    assert.deepEqual(result.private_review_relations_accessible, []);
    assert(!result.expected_client_functions_unavailable.some(name => name.includes('screening_permission')));
    await db.exec(`
      create function public.set_content_screening_permission(boolean,text)
        returns boolean language sql security definer set search_path='' as $$select true$$;
      revoke all on function public.set_content_screening_permission(boolean,text) from public;
      grant execute on function public.set_content_screening_permission(boolean,text) to authenticated;
      grant execute on function content_safety.screening_permission_matches(uuid,bigint) to authenticated;
    `);
    result = await inspect(db);
    assert.deepEqual(result.unexpected_client_privileged_functions, [
      'content_safety.screening_permission_matches(uuid,bigint)',
      'set_content_screening_permission(boolean,text)',
    ]);
  } finally { await db.close(); }
});

test('default PUBLIC and inherited grants expose privileged endpoints', async () => {
  const db = await fixture();
  try {
    await db.exec(`create function public.accidental_admin() returns integer language sql
      security definer as $$select 1$$;
      create role inherited_access;
      grant inherited_access to authenticated;
      grant execute on function public.preview_content_report(uuid) to inherited_access;`);
    const result = await inspect(db);
    assert(result.anonymous_privileged_functions.some(name => name.includes('accidental_admin')));
    assert(result.unexpected_client_privileged_functions.some(name => name.includes('accidental_admin')));
    assert(result.unexpected_client_privileged_functions.some(name => name.includes('preview_content_report')));
    assert(result.privileged_functions_without_fixed_search_path.some(name => name.includes('accidental_admin')));
  } finally { await db.close(); }
});

test('new overloads are not covered by the known function name', async () => {
  const db = await fixture();
  try {
    await db.exec(`create function public.list_safety_members(uuid) returns integer language sql
      security definer set search_path='' as $$select 1$$;
      revoke all on function public.list_safety_members(uuid) from public;
      grant execute on function public.list_safety_members(uuid) to authenticated;`);
    const result = await inspect(db);
    assert.equal(result.unexpected_client_privileged_functions.length,1);
    assert.match(result.unexpected_client_privileged_functions[0],/list_safety_members\(uuid\)/);
  } finally { await db.close(); }
});

test('schema writes, missing RLS and public buckets are reported without reading memories', async () => {
  const db = await fixture();
  try {
    await db.exec(`grant create on schema public to public;
      alter table public.memories disable row level security;
      update storage.buckets set public=true;`);
    const result = await inspect(db);
    assert.deepEqual(result.client_writable_schemas,['anon:public','authenticated:public']);
    assert.deepEqual(result.client_tables_without_rls,['authenticated:public.memories']);
    assert.deepEqual(result.public_storage_buckets,['vault_photos']);
  } finally { await db.close(); }
});

test('owner-rights views and materialized views differ from security-invoker views', async () => {
  const db = await fixture();
  try {
    await db.exec(`create view public.owner_view as select * from public.memories;
      create view public.caller_view with(security_invoker=true) as select * from public.memories;
      create materialized view public.snapshot as select * from public.memories;
      grant select on public.owner_view,public.caller_view,public.snapshot to authenticated;`);
    const result = await inspect(db);
    assert.deepEqual(result.client_views_bypassing_rls,['authenticated:public.owner_view','authenticated:public.snapshot']);
  } finally { await db.close(); }
});

test('private audit access is flagged even with RLS or only column grants', async () => {
  const db = await fixture();
  try {
    await db.exec(`grant select(id) on content_safety.preview_access to authenticated;`);
    assert.deepEqual((await inspect(db)).private_review_relations_accessible,['authenticated:content_safety.preview_access']);
    await db.exec(`revoke select(id) on content_safety.preview_access from authenticated;
      grant select on content_safety.preview_access to anon;`);
    assert.deepEqual((await inspect(db)).private_review_relations_accessible,['anon:content_safety.preview_access']);
  } finally { await db.close(); }
});

test('column-only grants cannot conceal unprotected tables or owner-rights views', async () => {
  const db = await fixture();
  try {
    await db.exec(`revoke select on public.memories from authenticated;
      alter table public.memories disable row level security;
      grant select(id) on public.memories to authenticated;
      create view public.owner_view as select * from public.memories;
      grant select(id) on public.owner_view to authenticated;`);
    const result = await inspect(db);
    assert.deepEqual(result.client_tables_without_rls,['authenticated:public.memories']);
    assert.deepEqual(result.client_views_bypassing_rls,['authenticated:public.owner_view']);
  } finally { await db.close(); }
});

test('derived-index writes are flagged even behind RLS or through column-only grants',async()=>{
  const db=await fixture();try{
    await db.exec(`create table public.memory_chunks(chunk_text text);
      alter table public.memory_chunks enable row level security;
      grant update(chunk_text) on public.memory_chunks to authenticated;`);
    assert.deepEqual((await inspect(db)).client_writable_derived_indexes,['authenticated:public.memory_chunks']);
    await db.exec('revoke update(chunk_text) on public.memory_chunks from authenticated; grant select on public.memory_chunks to authenticated;');
    assert.deepEqual((await inspect(db)).client_writable_derived_indexes,[]);
  }finally{await db.close();}
});
