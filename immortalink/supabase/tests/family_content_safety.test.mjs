import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261013104043_family_content_safety.sql', import.meta.url), 'utf8');
const attributionCleanup = await readFile(new URL('../migrations/20261013122650_safety_attribution_deletion_cleanup.sql', import.meta.url), 'utf8');
const ids = Array.from({ length: 12 }, (_, n) => `00000000-0000-4000-8000-${String(n + 1).padStart(12, '0')}`);
const [alice, bob, outsider, family, otherFamily, vault, otherVault, legacy, memory, photo] = ids;
const sharedPath = `${alice}/${family}/legacy/${legacy}/gallery/photo.jpg`;
const personalPath = `${alice}/${vault}/photo.jpg`;

async function fixture() {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema storage;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',coalesce(current_setting('test.role',true),'authenticated'))$$;
    create table family_groups(id uuid primary key,name text);
    create table family_members(family_id uuid,user_id uuid references auth.users(id) on delete cascade);
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid,name text,display_name text,created_at timestamptz default now());
    create table legacy_family_members(id uuid primary key,family_id uuid,avatar_path text);
    create table legacy_memories(id uuid primary key,legacy_member_id uuid,family_id uuid,body text);
    create table storage.objects(bucket_id text,name text);
    create table legacy_memory_chunks(id uuid,legacy_member_id uuid,legacy_memory_id uuid);
    insert into auth.users values('${alice}'),('${bob}'),('${outsider}');
    insert into family_groups values('${family}','Our family'),('${otherFamily}','Other family');
    insert into family_members values('${family}','${alice}'),('${family}','${bob}'),('${otherFamily}','${outsider}');
    insert into vaults(id,owner_id,family_id,name) values('${vault}','${alice}','${family}','Alice'),('${otherVault}','${outsider}','${otherFamily}','Outsider');
    insert into legacy_family_members values('${legacy}','${family}',null);
    insert into legacy_memories values('${memory}','${legacy}','${family}','Retained text');
    insert into storage.objects values('vault_photos','${sharedPath}'),('vault_photos','${personalPath}');`);
  const personal = ['memories', 'memory_photos', 'memory_voice_notes', 'vault_highlight_photos', 'vault_about_photos',
    'vault_core_voice_note', 'vault_voice_notes', 'voice_notes', 'vault_media', 'memory_chunks'];
  const legacyMedia = ['legacy_member_photos', 'legacy_memory_photos', 'legacy_memory_voice_notes', 'legacy_vault_about_photos', 'legacy_vault_core_voice_note'];
  for (const table of personal) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid(),vault_id uuid,path text);`);
  }
  for (const table of legacyMedia) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid(),legacy_member_id uuid,legacy_memory_id uuid,path text);`);
  }
  await db.exec(`insert into legacy_member_photos values('${photo}','${legacy}',null,'${sharedPath}');
    insert into memories(vault_id) values('${vault}');
    insert into memory_chunks(vault_id) values('${vault}');
    insert into legacy_memory_chunks values(gen_random_uuid(),'${legacy}','${memory}');
    grant usage on schema auth,storage to authenticated,anon,service_role;
    grant select,insert,update,delete on all tables in schema public to authenticated;
    grant select,insert,update on storage.objects to authenticated;`);
  // Deliberately permissive fixtures prove the new restrictive ceiling cannot
  // be bypassed by a second existing permissive policy.
  for (const table of [...personal, ...legacyMedia, 'vaults', 'legacy_family_members', 'legacy_memories', 'legacy_memory_chunks']) {
    await db.exec(`alter table ${table} enable row level security;
      create policy fixture_read on ${table} for all to authenticated using(true) with check(true);`);
  }
  await db.exec(`alter table storage.objects enable row level security;
    create policy fixture_read on storage.objects for all to authenticated using(true) with check(true);`);
  await db.exec(migration);
  await asUser(db, bob);
  return db;
}
async function asUser(db, id) {
  await db.exec(`reset role; set role authenticated;
    select set_config('test.role','authenticated',false);`);
  await db.query("select set_config('test.uid',$1,false)", [id]);
}
async function review(db, reportId, action) {
  await db.exec('reset role; set role service_role');
  await db.query("select review_content_report($1,$2,'QA operator','Reviewed the report')", [reportId, action]);
  await asUser(db, bob);
}
async function report(db, kind = 'vault', target = vault, familyId = null) {
  return (await db.query("select report_family_content($1,$2,'privacy','Please review',$3) id", [kind, target, familyId])).rows[0].id;
}

test('reports validate family access, are idempotent and private; clients cannot moderate', async () => {
  const db = await fixture(); try {
    const id = await report(db);
    assert.equal(await report(db), id);
    assert.equal((await db.query('select * from content_reports')).rows.length, 1);
    await assert.rejects(report(db, 'vault', otherVault), /CONTENT_UNAVAILABLE/);
    await assert.rejects(report(db, 'member', outsider, family), /CONTENT_UNAVAILABLE/);
    await assert.rejects(db.query("select report_family_content('vault',$1,'invalid')", [vault]), /INVALID_REPORT/);
    await assert.rejects(db.query("select report_family_content('vault',$1,'other',$2)", [vault, 'x'.repeat(1001)]), /INVALID_REPORT/);
    await assert.rejects(db.query("update content_reports set status='resolved'"), /permission denied/);
    await assert.rejects(db.query("select review_content_report($1,'hide','forged','forged')", [id]), /permission denied/);
    await assert.rejects(db.query('select * from content_safety.restrictions'), /permission denied/);
    await asUser(db, alice);
    assert.equal((await db.query('select * from content_reports')).rows.length, 0);
    await db.exec('reset role; set role anon');
    await assert.rejects(db.query('select list_safety_members()'), /permission denied/);
  } finally { await db.close(); }
});

test('blocks apply mutually to rows, AI chunks, helper RPCs and storage; unrelated scope is denied', async () => {
  const db = await fixture(); try {
    assert.equal((await db.query('select * from memories')).rows.length, 1);
    await assert.rejects(db.query('select set_member_block($1,true)', [outsider]), /INVALID_MEMBER/);
    await assert.rejects(db.query('select set_member_block($1,true)', [bob]), /INVALID_MEMBER/);
    await db.query('select set_member_block($1,true)', [alice]);
    await db.query('select set_member_block($1,true)', [alice]);
    assert.equal((await db.query('select * from member_blocks')).rows.length, 1);
    assert.equal((await db.query('select * from memories')).rows.length, 0);
    assert.equal((await db.query('select * from memory_chunks')).rows.length, 0);
    assert.deepEqual((await db.query('select can_read_vault_media($1) a,shares_family_with_vault($1) b', [vault])).rows, [{ a: false, b: false }]);
    assert.equal((await db.query('select * from storage.objects')).rows.length, 0);
    const members = (await db.query('select * from list_safety_members()')).rows;
    assert.equal(members.length, 1); assert.equal(members[0].blocked, true);
    await asUser(db, alice);
    assert.equal((await db.query("select content_safety.visible('member',$1,$1) v", [bob])).rows[0].v, false);
    await asUser(db, bob);
    await db.query('select set_member_block($1,false)', [alice]);
    assert.equal((await db.query('select * from memories')).rows.length, 1);
    assert.equal((await db.query('select * from storage.objects')).rows.length, 2);
  } finally { await db.close(); }
});

test('new contribution authors cannot be forged; blocking and reviewed memory hiding cover attachments/chunks', async () => {
  const db = await fixture(); try {
    const fresh = ids[10];
    await asUser(db, alice);
    await db.query('insert into legacy_memories(id,legacy_member_id,family_id,body,contributor_id) values($1,$2,$3,$4,$5)', [fresh, legacy, family, 'New contribution', bob]);
    assert.equal((await db.query('select contributor_id from legacy_memories where id=$1', [fresh])).rows[0].contributor_id, alice);
    await assert.rejects(db.query('update legacy_memories set contributor_id=$1 where id=$2', [bob, fresh]), /AUTHOR_IMMUTABLE/);
    await assert.rejects(db.query('update legacy_memories set last_editor_id=$1 where id=$2', [bob, fresh]), /AUTHOR_IMMUTABLE/);
    await db.query('insert into legacy_memory_photos(legacy_member_id,legacy_memory_id,path) values($1,$2,$3)', [legacy, fresh, sharedPath]);
    await db.query('insert into legacy_memory_chunks values(gen_random_uuid(),$1,$2)', [legacy, fresh]);
    await asUser(db, bob);
    const id = await report(db, 'legacy_memory', fresh);
    await db.query('select set_member_block($1,true)', [alice]);
    assert.equal((await db.query('select * from legacy_memories where id=$1', [fresh])).rows.length, 0);
    assert.equal((await db.query('select * from legacy_memory_photos')).rows.length, 0);
    assert.equal((await db.query('select * from legacy_memory_chunks where legacy_memory_id=$1', [fresh])).rows.length, 0);
    // Other authors and unattributed retained memories are not erased.
    assert.equal((await db.query('select * from legacy_memories where id=$1', [memory])).rows.length, 1);
    await db.query('select set_member_block($1,false)', [alice]);
    await review(db, id, 'hide');
    assert.equal((await db.query('select * from legacy_memories where id=$1', [fresh])).rows.length, 0);
    assert.equal((await db.query('select * from storage.objects where name=$1', [sharedPath])).rows.length, 0);
    await review(db, id, 'restore');
    assert.equal((await db.query('select * from legacy_memories where id=$1', [fresh])).rows.length, 1);
    assert.equal((await db.query('select * from storage.objects where name=$1', [sharedPath])).rows.length, 1);
    await db.exec('reset role');
    assert.equal((await db.query('select * from content_safety.review_actions')).rows.length, 2);
  } finally { await db.close(); }
});

test('reporting alone does not hide content; suspension rejects publication without deleting contributions', async () => {
  const db = await fixture(); try {
    const id = await report(db);
    assert.equal((await db.query('select * from memories')).rows.length, 1);
    await review(db, id, 'suspend');
    assert.equal((await db.query('select * from memories')).rows.length, 0);
    await asUser(db, alice);
    await assert.rejects(db.query('insert into memories(vault_id) values($1)', [vault]), /ACCOUNT_RESTRICTED/);
    await assert.rejects(db.query("insert into storage.objects values('vault_photos','new.jpg')"), /row-level security/);
    await review(db, id, 'reinstate');
    assert.equal((await db.query('select * from memories')).rows.length, 1);
    const legacyReport = await report(db, 'legacy_profile', legacy);
    await assert.rejects(review(db, legacyReport, 'suspend'), /AUTHOR_UNKNOWN/);
    await asUser(db, alice);
    await db.query('insert into legacy_memories(id,legacy_member_id,family_id,body) values($1,$2,$3,$4)', [ids[10], legacy, family, 'Keep after deletion']);
    await db.exec(`reset role; select set_config('test.role','service_role',false)`);
    await db.query('delete from auth.users where id=$1', [alice]);
    assert.equal((await db.query('select contributor_id from legacy_memories where id=$1', [ids[10]])).rows[0].contributor_id, null);
    assert.equal((await db.query('select * from legacy_memories')).rows.length, 2);
  } finally { await db.close(); }
});

test('report rate limit and unblock after family departure remain enforceable', async () => {
  const db = await fixture(); try {
    await db.query('select set_member_block($1,true)', [alice]);
    await db.exec('reset role');
    await db.query('delete from family_members where user_id=$1', [alice]);
    await asUser(db, bob);
    assert.equal((await db.query('select * from list_safety_members()')).rows[0].family_id, null);
    await db.query('select set_member_block($1,false)', [alice]);
    assert.equal((await db.query('select * from member_blocks')).rows.length, 0);
    await db.exec('reset role');
    await db.query(`insert into content_reports(reporter_id,family_id,target_kind,target_id,reason,status)
      select $1,$2,'vault',gen_random_uuid(),'other','resolved' from generate_series(1,10)`, [bob, family]);
    await asUser(db, bob);
    await assert.rejects(report(db, 'legacy_profile', legacy), /REPORT_LIMIT/);
  } finally { await db.close(); }
});

test('editing an old unattributed memory records its editor and obeys the block', async () => {
  const db = await fixture(); try {
    await db.query('select set_member_block($1,true)', [alice]);
    await asUser(db, alice);
    await db.query("update legacy_memories set body='An edited contribution' where id=$1", [memory]);
    assert.deepEqual((await db.query('select contributor_id,last_editor_id from legacy_memories where id=$1', [memory])).rows,
      [{ contributor_id: null, last_editor_id: alice }]);
    await asUser(db, bob);
    assert.equal((await db.query('select * from legacy_memories where id=$1', [memory])).rows.length, 0);
    assert.equal((await db.query('select * from legacy_memory_chunks')).rows.length, 0);
  } finally { await db.close(); }
});

test('auth FK cleanup preserves shared media without bypassing normal edit checks', async () => {
  const db = await fixture(); try {
    await asUser(db, alice);
    await db.query('insert into legacy_memory_voice_notes(id,legacy_member_id,path) values($1,$2,$3)', [ids[10], legacy, sharedPath]);
    await db.exec('reset role');
    await db.exec(attributionCleanup);
    await db.exec(`create trigger media_reference_scope_guard before insert or update on legacy_memory_voice_notes
      for each row execute function guard_media_reference_scope()`);
    // Match Auth's connection: no end-user identity and no service-role JWT.
    await db.exec("select set_config('test.uid','',false); select set_config('test.role','',false)");
    await assert.rejects(db.query('update legacy_memory_voice_notes set contributor_id=null'), /MEDIA_FAMILY_MISMATCH/);
    await assert.rejects(db.query('update legacy_memory_voice_notes set last_editor_id=null'), /MEDIA_FAMILY_MISMATCH/);
    await assert.rejects(db.query("update legacy_memory_voice_notes set path='forged'"), /MEDIA_FAMILY_MISMATCH/);
    await db.query('delete from auth.users where id=$1', [alice]);
    assert.deepEqual((await db.query('select contributor_id,last_editor_id,path from legacy_memory_voice_notes')).rows,
      [{ contributor_id: null, last_editor_id: null, path: sharedPath }]);
    await asUser(db, outsider);
    await assert.rejects(db.query("update legacy_memory_voice_notes set path='forged'"), /MEDIA_FAMILY_MISMATCH/);
    await db.exec('reset role');
    assert.equal((await db.query('select * from legacy_memory_voice_notes')).rows.length, 1);
  } finally { await db.close(); }
});
