import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261013142233_content_report_alerts.sql', import.meta.url), 'utf8');
const singleUse = await readFile(new URL('../migrations/20261013144031_single_use_report_alert_dispatch.sql', import.meta.url), 'utf8');
const health = await readFile(new URL('../migrations/20261013145108_report_alert_operator_health.sql', import.meta.url), 'utf8');
const report = '00000000-0000-4000-8000-000000000001';
const provider = '00000000-0000-4000-8000-000000000002';
async function fixture() {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema content_safety; grant usage on schema content_safety to authenticated,service_role;
    create schema vault; create table vault.secrets(name text);
    create schema cron;
    create table cron.job(jobid int,jobname text,active boolean);
    create table cron.job_run_details(jobid int,status text,start_time timestamptz);
    insert into cron.job values(1,'content-report-alerts',true);
    insert into cron.job_run_details values(1,'succeeded',now());
    create table public.content_reports(id uuid primary key default gen_random_uuid(),status text default 'open');`);
  await db.exec(migration);
  await db.exec(singleUse);
  await db.exec(health);
  await db.query('update content_safety.alert_config set enabled=true');
  await db.query('insert into content_reports(id) values($1)', [report]);
  return db;
}
async function authorize(db, reportId) {
  const value = randomBytes(32).toString('hex');
  await db.query("insert into content_safety.alert_invocations(token_hash,report_id) values(encode(sha256(convert_to($1,'UTF8')),'hex'),$2)", [value, reportId]);
  return value;
}
async function claim(db, value) {
  if (value === undefined) {
    const rows = (await db.query("select report_id from content_safety.report_alerts order by (state='pending') desc,created_at limit 1")).rows;
    value = await authorize(db, rows[0].report_id);
  }
  return (await db.query('select claim_content_report_alert($1) job', [value])).rows[0].job;
}
async function finish(db, job, result = 'ACCEPTED', id = provider) {
  return (await db.query('select finish_content_report_alert($1,$2,$3,$4) ok', [job.report_id, job.lease_id, result, id])).rows[0].ok;
}

test('report insertion queues once; clients cannot see or process alerts', async () => {
  const db = await fixture(); try {
    assert.equal((await db.query('select * from content_safety.report_alerts')).rows.length, 1);
    for (const role of ['anon', 'authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(db.query('select * from content_safety.report_alerts'), /permission denied/);
      await assert.rejects(claim(db), /permission denied/);
      await assert.rejects(finish(db, { report_id: report, lease_id: provider }), /permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role service_role');
    await assert.rejects(claim(db, 'b'.repeat(64)), /UNAUTHORIZED/);
    assert.equal((await claim(db)).report_id, report);
  } finally { await db.close(); }
});

test('operator health is private and flags stalled, failed, disabled and budget-limited alerts', async () => {
  const db = await fixture(); try {
    const inspect = async () => (await db.query('select content_report_alert_health() health')).rows[0].health;
    for (const role of ['anon', 'authenticated']) {
      await db.exec(`set role ${role}`);
      await assert.rejects(inspect(), /permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role service_role');
    let result = await inspect();
    assert.equal(result.needs_attention, false); assert.equal(result.pending, 1);
    assert.equal(result.open_reports, 1); assert.deepEqual(result.failed_references, []);
    await db.exec('reset role');
    await db.exec('update content_safety.alert_config set attempts_today=40');
    assert.equal((await inspect()).needs_attention, true);
    await db.exec("update content_safety.alert_config set budget_day=(now() at time zone 'UTC')::date-1");
    assert.equal((await inspect()).attempts_today, 0);
    assert.equal((await inspect()).needs_attention, false);
    await db.exec("update content_safety.report_alerts set state='failed',result_code='REVIEW_REQUIRED'");
    result = await inspect();
    assert.equal(result.needs_attention, true);
    assert.deepEqual(result.failed_references, [{ report_id: report, result_code: 'REVIEW_REQUIRED', attempts: 0 }]);
    await db.exec("update content_safety.report_alerts set state='sent'");
    assert.equal((await inspect()).needs_attention, false);
    await db.exec("update cron.job_run_details set start_time=now()-interval '6 minutes'");
    assert.equal((await inspect()).needs_attention, true);
    await db.exec('update cron.job_run_details set start_time=now(); update cron.job set active=false');
    assert.equal((await inspect()).scheduler_active, false);
    await db.exec('update cron.job set active=true; update content_safety.alert_config set enabled=false');
    assert.equal((await inspect()).needs_attention, true);
  } finally { await db.close(); }
});

test('claims are exclusive; correct live lease and valid acceptance are required', async () => {
  const db = await fixture(); try {
    const job = await claim(db);
    assert.equal(await claim(db), null);
    assert.equal(await finish(db, { ...job, lease_id: provider }), false);
    await assert.rejects(finish(db, job, 'ACCEPTED', null), /INVALID_ALERT_RESULT/);
    assert.equal(await finish(db, job), true);
    assert.equal(await finish(db, job), false);
    const row = (await db.query('select * from content_safety.report_alerts')).rows[0];
    assert.equal(row.state, 'sent'); assert.equal(row.provider_id, provider);
    assert.ok(row.accepted_at); assert.equal(await claim(db), null);
  } finally { await db.close(); }
});

test('crash recovery changes lease, preserves attempt history and stops before idempotency expiry', async () => {
  const db = await fixture(); try {
    const first = await claim(db);
    await db.exec("update content_safety.report_alerts set lease_until=now()-interval '1 minute'");
    const next = await claim(db);
    assert.notEqual(first.lease_id, next.lease_id); assert.equal(next.attempt, 2);
    assert.equal(await finish(db, first), false);
    await db.exec("update content_safety.report_alerts set lease_until=now()-interval '1 minute',first_attempt_at=now()-interval '23 hours 1 minute'");
    assert.equal(await claim(db), null);
    assert.equal((await db.query('select state from content_safety.report_alerts')).rows[0].state, 'failed');
  } finally { await db.close(); }
});

test('retry backoff, maximum attempts and permanent rejection are bounded', async () => {
  const db = await fixture(); try {
    for (let attempt = 1; attempt <= 5; attempt++) {
      const job = await claim(db); assert.equal(job.attempt, attempt);
      assert.equal(await finish(db, job, 'RETRY', null), true);
      assert.equal(await claim(db), null);
      await db.exec("update content_safety.report_alerts set next_attempt_at=now()-interval '1 minute'");
    }
    assert.equal((await db.query('select state from content_safety.report_alerts')).rows[0].state, 'failed');
    await db.query('insert into content_reports(id) values($1)', [provider]);
    const job = await claim(db); await finish(db, job, 'REJECTED', null);
    assert.equal(await claim(db), null);
  } finally { await db.close(); }
});

test('daily budget, disabled switch and closed reports do not send; report deletion cleans outbox', async () => {
  const db = await fixture(); try {
    await db.exec('update content_safety.alert_config set enabled=false'); assert.equal(await claim(db), null);
    await db.exec('update content_safety.alert_config set enabled=true,attempts_today=40'); assert.equal(await claim(db), null);
    await db.exec("update content_safety.alert_config set budget_day=(now() at time zone 'UTC')::date-1");
    assert.ok(await claim(db));
    assert.equal((await db.query('select attempts_today from content_safety.alert_config')).rows[0].attempts_today, 1);
    await db.query("insert into content_reports(id,status) values($1,'dismissed')", [provider]);
    assert.equal(await claim(db), null);
    assert.equal((await db.query('select state from content_safety.report_alerts where report_id=$1', [provider])).rows[0].state, 'skipped');
    await db.exec('delete from content_reports');
    assert.equal((await db.query('select * from content_safety.report_alerts')).rows.length, 0);
  } finally { await db.close(); }
});

test('dispatch tokens are single-use, short-lived and bound to one report', async () => {
  const db = await fixture(); try {
    await db.query('insert into content_reports(id) values($1)', [provider]);
    const value = await authorize(db, provider);
    assert.equal((await claim(db, value)).report_id, provider);
    await assert.rejects(claim(db, value), /UNAUTHORIZED/);
    const expired = await authorize(db, report);
    await db.exec("update content_safety.alert_invocations set expires_at=now()-interval '1 second' where consumed_at is null");
    await assert.rejects(claim(db, expired), /UNAUTHORIZED/);
    await assert.rejects(claim(db, 'a'.repeat(64)), /UNAUTHORIZED/);
    assert.equal((await db.query('select attempts from content_safety.report_alerts where report_id=$1', [report])).rows[0].attempts, 0);
  } finally { await db.close(); }
});
