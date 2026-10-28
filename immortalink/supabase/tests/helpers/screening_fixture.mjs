import { readFile } from 'node:fs/promises';
import { fixture as mediaFixture, owner, memory, ids } from './retirement_fixture.mjs';

export const permissionSql = await readFile(new URL('../../migrations/20261023110215_content_screening_permission.sql', import.meta.url), 'utf8');
export const queueSql = await readFile(new URL('../../migrations/20261023164835_content_screening_queue.sql', import.meta.url), 'utf8');
export const processingSql = await readFile(new URL('../../migrations/20261023174955_content_screening_processing_budgets.sql', import.meta.url), 'utf8');
export const photoTicketsSql = await readFile(new URL('../../migrations/20261024092200_content_screening_photo_tickets.sql', import.meta.url), 'utf8');
export const sharingSql = await readFile(new URL('../../migrations/20261024111907_content_screening_share_requests.sql', import.meta.url), 'utf8');
export const policy = 'openai-safety-text-photo-2026-10-23';
export const stranger = ids[12];

export async function screeningFixture(db, enabled = true, processing = false) {
  db = await mediaFixture(db);
  await db.exec(`
    alter table memories add column created_at timestamptz default now();
    alter table memories add column share_to_family_feed boolean default true;
    alter table legacy_memories add column created_at timestamptz default now();
    delete from memory_voice_notes; delete from legacy_memory_voice_notes;
    update legacy_memories set contributor_id='${owner}',last_editor_id='${owner}';
    update legacy_memory_photos set contributor_id='${owner}',last_editor_id='${owner}';
    insert into auth.users values('${stranger}');
  `);
  await db.exec(permissionSql);
  await db.exec(queueSql);
  if (processing) await db.exec(processingSql);
  if (enabled) await db.exec(`update content_safety.screening_controls
    set enabled=true,eligible_after=now()-interval '1 minute';`);
  await consent(db, owner, true);
  return db;
}
export async function consent(db, user, allowed) {
  await db.exec('reset role; set role authenticated');
  await db.query("select set_config('test.uid',$1,false)", [user]);
  await db.query('select set_content_screening_permission($1,$2,$3)', [allowed, policy, user]);
  await db.exec('reset role');
  await db.query("select set_config('test.uid','',false)");
}
export async function rpc(db, sql, args = []) {
  await db.exec('set role service_role');
  try { return (await db.query(`select ${sql} as value`, args)).rows[0].value; }
  finally { await db.exec('reset role'); }
}
export const enqueue = (db, kind = 'memory', target = memory, actor = owner) =>
  rpc(db, 'enqueue_content_screening($1,$2,$3)', [kind, target, actor]);
export const claim = db => rpc(db, 'claim_content_screening()');
export const prepare = (db, job, authorize = false) =>
  rpc(db, 'prepare_content_screening($1,$2,$3)', [job.id, job.lease_token, authorize]);
export const finish = (db, job, outcome = 'clear') =>
  rpc(db, 'finish_content_screening($1,$2,$3)', [job.id, job.lease_token, outcome]);
export const clear = (db, kind = 'memory', target = memory) =>
  rpc(db, 'content_screening_revision_clear($1,$2)', [kind, target]);
export async function photoFixture(db, enabled = true) {
  db = await screeningFixture(db, enabled, true);
  await db.exec(photoTicketsSql);
  return db;
}
export const claimPhoto = (db, job, index = 0) =>
  rpc(db, 'claim_content_screening_photo($1,$2,$3)', [job.id, job.lease_token, index]);
export const finishPhoto = (db, ticket, bytes = 100, sha = 'a'.repeat(64)) =>
  rpc(db, 'finish_content_screening_photo($1,$2,$3)', [ticket, bytes, sha]);

export async function sharingFixture(db, { enabled = true, fresh = true } = {}) {
  db = await photoFixture(db, false);
  await db.exec(sharingSql);
  if (enabled) await db.exec(`update content_safety.screening_controls
    set enabled=true,eligible_after=clock_timestamp()-interval '1 minute'`);
  if (fresh) await freshTargets(db);
  return db;
}

// Replace only synthetic fixture rows with actual INSERTs after activation.
// Existing attachments are kept to exercise the same scoped source checks.
export async function freshTargets(db) {
  await db.exec(`
    create temporary table new_personal_fixture as table memories;
    create temporary table new_legacy_fixture as table legacy_memories;
    delete from memories; delete from legacy_memories;
    insert into memories select * from new_personal_fixture;
    insert into legacy_memories select * from new_legacy_fixture;
    drop table new_personal_fixture; drop table new_legacy_fixture;
  `);
}

export async function request(db, kind = 'memory', target = memory, user = owner, expected = user) {
  await db.exec('set role authenticated');
  await db.query("select set_config('test.uid',$1,false)", [user ?? '']);
  try {
    return (await db.query('select request_content_screening($1,$2,$3) value', [kind, target, expected])).rows[0].value;
  } finally {
    await db.exec('reset role');
    await db.query("select set_config('test.uid','',false)");
  }
}
