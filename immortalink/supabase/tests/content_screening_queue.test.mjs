import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fixture as mediaFixture, owner, viewer, family, legacy, vault, memory,
  sibling, legacyMemory, photoPath, ids } from './helpers/retirement_fixture.mjs';
import { screeningFixture, permissionSql, queueSql, consent, enqueue, claim,
  prepare, finish, clear } from './helpers/screening_fixture.mjs';

const audit = await readFile(new URL('../verification/launch_access_audit.sql', import.meta.url), 'utf8');

async function fixture(t, enabled = true) {
  const db = await screeningFixture(undefined, enabled);
  t.after(() => db.close());
  return db;
}
async function dispatched(db, kind = 'memory', target = memory) {
  await enqueue(db, kind, target);
  const job = await claim(db);
  assert.equal((await prepare(db, job)).code, 'READY');
  assert.equal((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
  return job;
}
async function runnable(db) {
  await db.exec(`update content_safety.screening_jobs set available_at=now()-interval '1 minute',
    lease_until=case when state='leased' then now()-interval '1 minute' else null end;`);
}

test('queue is off by default, has no archive scan, network call or publication hook', async t => {
  const db = await fixture(t, false);
  assert.equal((await enqueue(db)).code, 'SCREENING_DISABLED');
  assert.equal(await claim(db), null);
  assert.equal(await clear(db), false);
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_jobs')).rows[0].n, 0);
  assert.doesNotMatch(queueSql, /create\s+(trigger|policy)|net\.http|cron\.|fetch\(/i);
  await db.exec('update content_safety.screening_controls set enabled=true');
  assert.equal((await enqueue(db)).code, 'SCREENING_DISABLED');
});

test('migration leaves every existing function, policy, trigger and media row unchanged', async t => {
  const db = await mediaFixture();
  t.after(() => db.close());
  await db.exec(permissionSql);
  const functions = (await db.query(`select p.oid,pg_get_functiondef(p.oid) body
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','content_safety') and p.prokind='f' order by p.oid`)).rows;
  const policies = (await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows;
  const triggers = (await db.query('select oid,pg_get_triggerdef(oid) body from pg_trigger order by oid')).rows;
  const objects = (await db.query('select * from storage.objects order by id')).rows;
  await db.exec(queueSql);
  for (const f of functions) {
    assert.equal((await db.query('select pg_get_functiondef($1) body', [f.oid])).rows[0].body, f.body);
  }
  assert.deepEqual((await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows, policies);
  // New queue FKs add only internal triggers on auth.users and the new queue.
  for (const tr of triggers) assert.equal((await db.query('select pg_get_triggerdef($1) body', [tr.oid])).rows[0].body, tr.body);
  assert.deepEqual((await db.query('select * from storage.objects order by id')).rows, objects);
});

test('only new explicitly shared targets and an actual contributor can enter the queue', async t => {
  const db = await fixture(t);
  assert.equal((await enqueue(db, 'vault', vault)).code, 'UNSUPPORTED_TARGET');
  assert.equal((await enqueue(db, 'memory', memory, viewer)).code, 'ACTOR_MISMATCH');
  assert.equal((await enqueue(db, 'memory', memory, null)).code, 'ACTOR_MISMATCH');
  await db.exec("update memories set share_to_family_feed=false");
  assert.equal((await enqueue(db)).code, 'NOT_REQUESTED_FOR_SHARING');
  await db.exec("update memories set share_to_family_feed=true,created_at=now()-interval '1 year'");
  assert.equal((await enqueue(db)).code, 'ARCHIVE_EXCLUDED');
  await db.exec("update legacy_memories set created_at=now()-interval '1 year'");
  assert.equal((await enqueue(db, 'legacy_memory', legacyMemory)).code, 'ARCHIVE_EXCLUDED');
  assert.equal((await db.query('select body from memories where id=$1', [memory])).rows[0].body, 'Reported');
});

test('duplicate enqueue/claim is idempotent and content requires the exact lease', async t => {
  const db = await fixture(t);
  const first = await enqueue(db);
  assert.deepEqual(await enqueue(db), first);
  const job = await claim(db);
  assert.deepEqual(Object.keys(job).sort(), ['id', 'lease_token', 'revision']);
  assert.equal(await claim(db), null);
  assert.equal((await prepare(db, { ...job, lease_token: ids[13] })).code, 'LEASE_UNAVAILABLE');
  const payload = await prepare(db, job);
  assert.equal(payload.text, 'QA\nReported');
  assert.equal(payload.images[0].path, photoPath);
  assert.match(payload.revision, /^[0-9a-f]{64}$/);
  assert.equal((await enqueue(db)).state, 'leased');
  assert.equal((await finish(db, job)).code, 'LEASE_UNAVAILABLE');
  assert.equal((await prepare(db, job, true)).code, 'DISPATCH_RESERVED');
  assert.equal((await prepare(db, job, true)).code, 'LEASE_UNAVAILABLE');
  assert.equal((await finish(db, job)).state, 'clear');
  assert.equal((await finish(db, job)).code, 'LEASE_UNAVAILABLE');
  assert.equal(await clear(db), true);
  assert.equal((await enqueue(db)).state, 'clear');
  assert.equal(await claim(db), null);
  const stored = (await db.query('select to_jsonb(j) j from content_safety.screening_jobs j')).rows[0].j;
  assert(!JSON.stringify(stored).includes('Reported'));
  assert(!JSON.stringify(stored).includes(photoPath));
});

test('withdrawal before claim, before dispatch and during processing cannot result in clear', async t => {
  for (const stage of ['queued', 'claimed', 'dispatched']) {
    await t.test(stage, async t => {
      const db = await fixture(t);
      await enqueue(db);
      const job = stage === 'queued' ? null : await claim(db);
      if (stage === 'dispatched') await prepare(db, job, true);
      await consent(db, owner, false);
      await consent(db, owner, true);
      if (!job) assert.equal(await claim(db), null);
      else if (stage === 'claimed') assert.equal((await prepare(db, job, true)).code, 'SOURCE_CHANGED');
      else assert.equal((await finish(db, job)).state, 'stale');
      assert.equal(await clear(db), false);
    });
  }
});

test('edits, new attachments and replaced bytes invalidate a previously clear revision', async t => {
  for (const change of [
    "update memories set body='Changed'",
    "update storage.objects set metadata=jsonb_set(metadata,'{eTag}','\"different\"')",
    `delete from memory_photos where memory_id='${memory}'`,
    `insert into memory_voice_notes(memory_id,vault_id,path) values('${memory}','${vault}','${photoPath}')`,
    `update memories set share_to_family_feed=false where id='${memory}'`,
    `delete from family_members where user_id='${owner}'`,
    `insert into account_deletion_jobs(user_id,lease_token,lease_until) values('${owner}','${ids[15]}',now()+interval '2 minutes')`,
  ]) {
    await t.test(change.split(' ').slice(0, 3).join(' '), async t => {
      const db = await fixture(t);
      const job = await dispatched(db);
      await finish(db, job);
      assert.equal(await clear(db), true);
      await db.exec(change);
      assert.equal(await clear(db), false);
    });
  }
});

test('changed source during processing rejects old completion and requires a new revision', async t => {
  const db = await fixture(t);
  const old = await dispatched(db);
  await db.exec("update memories set body='New version'");
  assert.equal((await finish(db, old)).state, 'stale');
  await enqueue(db);
  const fresh = await claim(db);
  assert.notEqual(fresh.revision, old.revision);
  assert.notEqual(fresh.lease_token, old.lease_token);
  assert.equal((await finish(db, old)).code, 'LEASE_UNAVAILABLE');
  await prepare(db, fresh, true);
  assert.equal((await finish(db, fresh)).state, 'clear');
});

test('legacy text and each photo contributor require their own current permission', async t => {
  const db = await fixture(t);
  await db.query('update legacy_memory_photos set contributor_id=$1,last_editor_id=$1', [viewer]);
  assert.equal((await enqueue(db, 'legacy_memory', legacyMemory)).code, 'PERMISSION_REQUIRED');
  await consent(db, viewer, true);
  const job = await dispatched(db, 'legacy_memory', legacyMemory);
  await consent(db, viewer, false);
  assert.equal((await finish(db, job)).state, 'stale');
  await consent(db, viewer, true);
  await db.exec('update legacy_memory_photos set contributor_id=null');
  assert.equal((await enqueue(db, 'legacy_memory', legacyMemory)).code, 'ATTRIBUTION_UNAVAILABLE');
});

test('legacy completion cannot survive family changes or attribution/deletion changes', async t => {
  const db = await fixture(t);
  const job = await dispatched(db, 'legacy_memory', legacyMemory);
  await db.query('delete from family_members where user_id=$1', [owner]);
  assert.equal((await finish(db, job)).state, 'stale');
  assert.equal(await clear(db, 'legacy_memory', legacyMemory), false);
  assert.equal((await db.query('select body from legacy_memories')).rows[0].body, 'Legacy');
});

test('a second contributor cannot reset a review or retry limit for the same revision', async t => {
  const db = await fixture(t);
  await consent(db, viewer, true);
  await db.query('update legacy_memories set last_editor_id=$1', [viewer]);
  const job = await dispatched(db, 'legacy_memory', legacyMemory);
  await finish(db, job, 'review');
  const same = await enqueue(db, 'legacy_memory', legacyMemory, viewer);
  assert.equal(same.id, job.id);
  assert.equal(same.state, 'review');
  assert.equal(await claim(db), null);
});

test('sexual reports and existing restrictions prevent provider authorization', async t => {
  const db = await fixture(t);
  const job = await dispatched(db);
  await db.query(`insert into content_reports(reporter_id,family_id,target_kind,target_id,reason,details)
    values($1,$2,'memory',$3,'sexual_content','QA')`, [viewer, family, memory]);
  assert.equal((await finish(db, job)).state, 'stale');
  assert.equal((await enqueue(db)).code, 'RESTRICTED_REVIEW_REQUIRED');
  await db.exec("update content_reports set status='dismissed'");
  assert.equal((await enqueue(db)).code, 'RESTRICTED_REVIEW_REQUIRED');
  await db.exec('delete from content_reports');
  await db.query("insert into content_safety.restrictions(target_kind,target_id) values('vault',$1)", [vault]);
  assert.equal((await enqueue(db)).code, 'RESTRICTED_TARGET');
});

test('voice, video, missing objects, unsafe sizes and oversized text never reach a request', async t => {
  for (const [mutation, expected] of [
    [`insert into memory_voice_notes(memory_id,vault_id,path) values('${memory}','${vault}','voice.m4a')`, 'VOICE_REVIEW_REQUIRED'],
    ["update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','\"video/mp4\"')", 'MEDIA_REVIEW_REQUIRED'],
    ["update storage.objects set metadata=jsonb_set(metadata,'{size}','\"not-a-number\"')", 'ATTACHMENT_SIZE_INVALID'],
    ["update storage.objects set metadata=jsonb_set(metadata,'{size}','12582913')", 'ATTACHMENT_SIZE_INVALID'],
    ['delete from storage.objects', 'ATTACHMENT_UNAVAILABLE'],
    ["update memories set body=repeat('a',20001)", 'TEXT_LIMIT'],
  ]) {
    await t.test(expected, async t => {
      const db = await fixture(t);
      // Inject impossible/corrupt metadata to exercise the queue's own ceiling,
      // separately from the real upload quota guard (covered by its own tests).
      if (expected === 'ATTACHMENT_SIZE_INVALID') await db.exec(
        'alter table storage.objects disable trigger everroot_storage_object_capacity_before_write');
      await db.exec(mutation);
      assert.equal((await enqueue(db)).code, expected);
      assert.equal(await claim(db), null);
    });
  }
});

test('global and per-person request budgets reserve once and survive worker retries', async t => {
  for (const limit of ['max_daily_requests', 'max_user_hourly_requests']) {
    await t.test(limit, async t => {
      const db = await fixture(t);
      await db.exec(`update content_safety.screening_controls set ${limit}=1`);
      const first = await dispatched(db);
      await finish(db, first, 'pending');
      await enqueue(db, 'memory', sibling);
      const second = await claim(db);
      assert.equal((await prepare(db, second, true)).code, 'BUDGET_LIMIT');
      assert.equal((await finish(db, second)).code, 'LEASE_UNAVAILABLE');
      assert.equal(await claim(db), null);
      const budgets = (await db.query('select used from content_safety.screening_budgets')).rows;
      assert.deepEqual(budgets.map(b => b.used), [1, 1]);
      await runnable(db);
      const retry = await claim(db);
      assert.equal((await prepare(db, retry, true)).code, 'BUDGET_LIMIT');
      await db.exec('update content_safety.screening_budgets set window_start=0');
      await runnable(db);
      const tomorrow = await claim(db);
      assert.equal((await prepare(db, tomorrow, true)).code, 'DISPATCH_RESERVED');
    });
  }
});

test('queue capacity is bounded, including items waiting for review', async t => {
  for (const limit of ['max_pending', 'max_user_pending']) {
    await t.test(limit, async t => {
      const db = await fixture(t);
      await db.exec(`update content_safety.screening_controls set ${limit}=1`);
      const job = await dispatched(db);
      await finish(db, job, 'review');
      assert.equal((await enqueue(db, 'memory', sibling)).code, 'QUEUE_LIMIT');
      assert.equal((await enqueue(db)).state, 'review');
    });
  }
});

test('expired leases are replaced, old workers are rejected and retries stop after three attempts', async t => {
  const db = await fixture(t);
  await enqueue(db);
  let previous;
  for (let n = 0; n < 3; n++) {
    const job = await claim(db);
    assert(job);
    if (previous) {
      assert.notEqual(job.lease_token, previous.lease_token);
      assert.equal((await prepare(db, previous, true)).code, 'LEASE_UNAVAILABLE');
    }
    await prepare(db, job, true);
    await runnable(db);
    assert.equal((await finish(db, job)).code, 'LEASE_UNAVAILABLE');
    previous = job;
  }
  assert.equal(await claim(db), null);
  assert.equal((await enqueue(db)).code, 'RETRY_LIMIT');
  assert.equal(await clear(db), false);
});

test('provider failures back off, flagged content stays in review, and disable fails closed', async t => {
  const db = await fixture(t);
  const first = await dispatched(db);
  assert.equal((await finish(db, first, 'pending')).state, 'queued');
  assert.equal(await claim(db), null);
  await runnable(db);
  const retry = await claim(db);
  await prepare(db, retry, true);
  assert.equal((await finish(db, retry, 'review')).state, 'review');
  assert.equal(await clear(db), false);
  await enqueue(db, 'memory', sibling);
  const another = await claim(db);
  await prepare(db, another, true);
  await db.exec('update content_safety.screening_controls set enabled=false');
  assert.equal((await finish(db, another)).state, 'stale');
  assert.equal(await clear(db, 'memory', sibling), false);
});

test('target deletion cannot be approved and account deletion removes its queued work', async t => {
  const db = await fixture(t);
  const job = await dispatched(db);
  await db.query('delete from memories where id=$1', [memory]);
  assert.equal((await finish(db, job)).state, 'stale');
  await db.query('delete from auth.users where id=$1', [owner]);
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_jobs')).rows[0].n, 0);
});

test('queue RPCs and relations deny clients; audit detects any accidental worker grant', async t => {
  const db = await fixture(t);
  for (const role of ['anon', 'authenticated']) {
    await db.exec(`set role ${role}`);
    for (const sql of [
      `select enqueue_content_screening('memory','${memory}','${owner}')`,
      'select claim_content_screening()',
      `select prepare_content_screening('${ids[15]}','${ids[16]}',true)`,
      `select finish_content_screening('${ids[15]}','${ids[16]}','clear')`,
      `select content_screening_revision_clear('memory','${memory}')`,
      `select content_safety.screening_snapshot('memory','${memory}','${owner}')`,
    ]) await assert.rejects(db.query(sql), /permission denied/);
    await db.exec('reset role');
  }
  await db.exec('set role service_role');
  for (const table of ['screening_controls', 'screening_jobs', 'screening_budgets']) {
    await assert.rejects(db.query(`select * from content_safety.${table}`), /permission denied/);
    await assert.rejects(db.query(`delete from content_safety.${table}`), /permission denied/);
  }
  await db.exec('reset role');
  const checks = await db.query(`select relrowsecurity rls from pg_class where oid in
    ('content_safety.screening_controls'::regclass,'content_safety.screening_jobs'::regclass,'content_safety.screening_budgets'::regclass)`);
  assert(checks.rows.every(r => r.rls));
  const results = (await db.query(audit)).rows;
  for (const check of results.filter(r => ['anonymous_privileged_functions', 'unexpected_client_privileged_functions'].includes(r.check_name))) {
    assert(!check.findings.some(f => f.includes('screening')), JSON.stringify(check));
  }
  await db.exec('grant execute on function public.claim_content_screening() to authenticated');
  const bad = (await db.query(audit)).rows.find(r => r.check_name === 'unexpected_client_privileged_functions');
  assert(bad.findings.some(f => f.includes('claim_content_screening')));
});
