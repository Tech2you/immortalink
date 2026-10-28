import { readFile } from 'node:fs/promises';
import { sharingFixture, request, claim, prepare, claimPhoto, finishPhoto, finish } from './screening_fixture.mjs';
import { owner, memory } from './retirement_fixture.mjs';

export const publicationSql = await readFile(new URL('../../migrations/20261024114120_content_screening_publication.sql', import.meta.url), 'utf8');
export async function publicationFixture(db, { enforce = true, ...options } = {}) {
  db = await sharingFixture(db, options);
  await db.exec(publicationSql);
  if (enforce) await db.exec('update content_safety.screening_controls set enforce_publication=true');
  // Existing permissive access is deliberately broad here: the added ceilings
  // must hold even if an old family SELECT policy allows all fixture rows.
  for (const table of ['memories','memory_photos','memory_voice_notes','memory_chunks',
    'legacy_memories','legacy_memory_photos','legacy_memory_voice_notes','legacy_memory_chunks','storage.objects']) {
    await db.exec(`alter table ${table} enable row level security;
      grant select on ${table} to authenticated;
      create policy fixture_read on ${table} for select to authenticated using(true)`);
  }
  await db.exec(`grant select on vaults,legacy_family_members,family_members to authenticated;
    grant insert,update on memories to authenticated;
    create policy fixture_insert on memories for insert to authenticated
      with check(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));
    create policy fixture_update on memories for update to authenticated
      using(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()))
      with check(exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));
    insert into memory_chunks(vault_id,memory_id) select vault_id,id from memories;
    insert into legacy_memory_chunks(id,legacy_member_id,legacy_memory_id) select gen_random_uuid(),legacy_member_id,id from legacy_memories;`);
  return db;
}
export async function asUser(db, user, sql, args = []) {
  await db.exec("set role authenticated; set test.role='authenticated'");
  await db.query("select set_config('test.uid',$1,false)", [user ?? '']);
  try { return await db.query(sql, args); }
  finally { await db.exec('reset role; reset test.role; reset test.uid'); }
}
export async function dispatched(db, kind = 'memory', target = memory, user = owner) {
  assertCode(await request(db, kind, target, user), 'QUEUED');
  const job = await claim(db);
  if (!job) throw new Error('Expected a claimed job');
  const source = await prepare(db, job);
  for (let i = 0; i < source.images.length; i++) {
    const ticket = await claimPhoto(db, job, i);
    assertCode(await finishPhoto(db, ticket.ticket_id), 'PHOTO_READY');
  }
  assertCode(await prepare(db, job, true), 'DISPATCH_RESERVED');
  return job;
}
function assertCode(value, code) {
  if (value?.code !== code) throw new Error(`Expected ${code}, got ${JSON.stringify(value)}`);
}
export async function approve(db, kind = 'memory', target = memory) {
  return finish(db, await dispatched(db, kind, target));
}
