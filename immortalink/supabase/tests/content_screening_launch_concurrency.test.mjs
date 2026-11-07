import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { deliveryFixture } from './helpers/delivery_fixture.mjs';
import { asUser } from './helpers/publication_fixture.mjs';
import { request, claim, prepare, finish, rpc, claimPhoto, finishPhoto } from './helpers/screening_fixture.mjs';
import { owner, viewer, memory, sibling } from './helpers/retirement_fixture.mjs';

const policy = 'openai-safety-text-photo-2026-11-05';
async function finalFixture(db) {
  await deliveryFixture(db, false);
  await db.exec(`create schema net;
    create table net.requests(id bigint generated always as identity,headers jsonb);
    create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer)
    returns bigint language sql as $$insert into net.requests(headers) values($2) returning id$$;`);
  for (const name of ['20261105172337_content_screening_launch_compatibility',
    '20261105173918_content_screening_worker_dispatch', '20261105180100_content_screening_material_edits',
    '20261105195157_content_screening_single_image_requests']) {
    await db.exec(await readFile(new URL(`../migrations/${name}.sql`, import.meta.url), 'utf8'));
  }
  await asUser(db, owner, 'select set_content_screening_permission(true,$1,$2)', [policy, owner]);
  await db.exec('create or replace function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1073741824::bigint$$');
}

test('final launch migrations serialize chunk budgets, publication, withdrawal and dispatcher wakeups', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-screening-launch-pg-');
  const listener = createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const pg = new EmbeddedPostgres({ databaseDir: `${directory}/data`, port, user: 'postgres',
    password: randomBytes(32).toString('hex'), persistent: false, createPostgresUser: false,
    postgresFlags: ['-h', '127.0.0.1', '-k', directory], onLog: () => {}, onError: () => {} });
  const clients = [];
  async function connect(name) {
    const db = pg.getPgClient(name, '127.0.0.1'); await db.connect(); clients.push(db);
    db.exec = sql => db.query(sql); await db.exec("set statement_timeout='10s';set lock_timeout='5s'");
    return db;
  }
  async function waiting(monitor, db) {
    for (let i = 0; i < 200; i++) {
      if ((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'", [db.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Concurrent operation did not wait for the tested lock');
  }
  try {
    await pg.initialise(); await pg.start();
    for (const [i, scenario] of ['whole-batch-budget', 'material-edit', 'withdrawal', 'single-dispatch'].entries()) {
      await t.test(scenario, async () => {
        const name = `launch_${i}`; await pg.createDatabase(name);
        const a = await connect(name), b = await connect(name), monitor = await connect(name);
        await finalFixture(a);
        let job, other, pending;
        if (scenario === 'whole-batch-budget') {
          await a.exec('delete from memory_photos');
          await a.query('update memories set body=$1', ['x'.repeat(50000)]);
          // The sibling predates capture; its material edit must enroll it.
          assert.equal((await request(a)).state, 'queued');
          job = await claim(a);
          assert.equal((await request(a, 'memory', sibling)).state, 'queued');
          other = await claim(a);
          assert(job?.id); assert(other?.id); assert.notEqual(job.id, other.id);
          await a.exec('update content_safety.screening_controls set max_daily_requests=13');
        } else {
          assert.equal((await request(a)).state, 'queued');
          if (scenario !== 'single-dispatch') {
            job = await claim(a);
            const ticket = await claimPhoto(a, job);
            assert.equal((await finishPhoto(a, ticket.ticket_id)).code, 'PHOTO_READY');
            assert.equal((await prepare(a, job, true)).requests_reserved, 1);
          } else await a.exec('update content_safety.screening_worker_config set enabled=true');
        }
        await a.exec('begin');
        try {
          if (scenario === 'whole-batch-budget') {
            assert.equal((await prepare(a, job, true)).requests_reserved, 13);
            pending = prepare(b, other, true);
          } else if (scenario === 'material-edit') {
            await a.query("update memories set body='A materially different story' where id=$1", [memory]);
            pending = finish(b, job);
          } else if (scenario === 'withdrawal') {
            await asUser(a, owner, 'select set_content_screening_permission(false,$1,$2)', [policy, owner]);
            pending = finish(b, job);
          } else {
            assert.match(String(await rpc(a, 'dispatch_content_screening()')), /^\d+$/);
            pending = rpc(b, 'dispatch_content_screening()');
          }
          pending = pending.then(value => ({ value }), error => ({ error }));
          await waiting(monitor, b); await a.exec('commit');
          const result = await pending; assert.ifError(result.error);
          if (scenario === 'whole-batch-budget') {
            assert.equal(result.value.code, 'BUDGET_LIMIT');
            assert.equal((await monitor.query("select used from content_safety.screening_budgets where scope='global_day'")).rows[0].used, 13);
          } else if (scenario === 'single-dispatch') {
            assert.equal(result.value, null);
            assert.equal((await monitor.query('select count(*)::int n from net.requests')).rows[0].n, 1);
            assert.equal((await monitor.query('select runs from content_safety.screening_worker_config')).rows[0].runs, 1);
          } else {
            assert.equal(result.value.state, 'stale');
            assert.equal((await asUser(monitor, viewer, 'select id from memories where id=$1', [memory])).rows.length, 0);
          }
        } finally { await a.exec('rollback'); await pending; }
        for (const db of clients.splice(0)) await db.end(); await pg.dropDatabase(name);
      });
    }
  } finally { for (const db of clients) await db.end().catch(() => {}); await pg.stop(); }
});
