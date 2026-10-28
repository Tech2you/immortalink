import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { owner, memory, sibling, ids } from './helpers/retirement_fixture.mjs';
import { screeningFixture, photoTicketsSql, enqueue, claim, prepare, finish, clear, consent, claimPhoto, finishPhoto } from './helpers/screening_fixture.mjs';

test('real PostgreSQL serializes screening leases, consent, source changes and budgets', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-screening-pg-');
  const listener = createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const pg = new EmbeddedPostgres({ databaseDir: `${directory}/data`, port,
    user: 'postgres', password: randomBytes(32).toString('hex'), persistent: false,
    createPostgresUser: false, postgresFlags: ['-h', '127.0.0.1', '-k', directory],
    onLog: () => {}, onError: () => {} });
  const clients = [];
  async function connect(name) {
    const c = pg.getPgClient(name, '127.0.0.1');
    await c.connect(); clients.push(c); c.exec = sql => c.query(sql);
    await c.query("set statement_timeout='10s'; set lock_timeout='5s'");
    return c;
  }
  async function waiting(monitor, client) {
    for (let i = 0; i < 200; i++) {
      const rows = (await monitor.query(
        "select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'", [client.processID])).rows;
      if (rows.length) return;
      await delay(10);
    }
    assert.fail('Second connection did not wait on the tested lock');
  }
  try {
    await pg.initialise(); await pg.start();
    for (const [index, scenario] of ['claim-once', 'edit-first', 'withdraw-first',
      'finish-first', 'budget-once', 'delete-first', 'processing-once', 'processing-limit',
      'photo-claim-once', 'photo-withdraw-first', 'photo-delete-first', 'photo-finish-first',
      'photo-reclaim-first', 'photo-finish-once'].entries()) {
      await t.test(scenario, async () => {
        const name = `screening_${index}`;
        await pg.createDatabase(name);
        const a = await connect(name), b = await connect(name), monitor = await connect(name);
        await screeningFixture(a, true, true);
        const photoTest = scenario.startsWith('photo-');
        if (photoTest) await a.exec(photoTicketsSql);
        await enqueue(a);
        const job = scenario === 'claim-once' ? null : await claim(a);
        if (job && !photoTest && !['budget-once', 'processing-once', 'processing-limit'].includes(scenario)) await prepare(a, job, true);
        const ticket = photoTest && scenario !== 'photo-claim-once' ? await claimPhoto(a, job) : null;
        if (scenario === 'photo-reclaim-first') await a.exec("update content_safety.screening_jobs set lease_until=now()-interval '1 minute'");
        let other;
        if (scenario === 'budget-once') {
          await a.query('update content_safety.screening_controls set max_daily_requests=1');
          await enqueue(a, 'memory', sibling); other = await claim(a);
        }
        if (scenario === 'processing-limit') {
          await a.query("update content_safety.screening_processing_limits set max_bytes=10 where scope='global_day'");
          await enqueue(a, 'memory', sibling); other = await claim(a);
        }
        await a.query('begin');
        let pending;
        try {
          if (scenario === 'photo-claim-once') {
            assert.equal((await claimPhoto(a, job)).code, 'PHOTO_CLAIMED'); pending = claimPhoto(b, job);
          } else if (scenario === 'photo-withdraw-first') {
            await consent(a, owner, false); pending = finishPhoto(b, ticket.ticket_id);
          } else if (scenario === 'photo-delete-first') {
            await a.query('select claim_account_deletion($1,$2)', [owner, ids[15]]); pending = finishPhoto(b, ticket.ticket_id);
          } else if (scenario === 'photo-finish-first' || scenario === 'photo-finish-once') {
            assert.equal((await finishPhoto(a, ticket.ticket_id)).code, 'PHOTO_READY');
            pending = scenario === 'photo-finish-first' ? consent(b, owner, false) : finishPhoto(b, ticket.ticket_id);
          } else if (scenario === 'photo-reclaim-first') {
            const next = await claim(a); assert(next);
            assert.equal((await claimPhoto(a, next)).code, 'PHOTO_CLAIMED'); pending = finishPhoto(b, ticket.ticket_id);
          } else if (scenario === 'claim-once') {
            assert(await claim(a)); pending = claim(b);
          } else if (scenario === 'edit-first') {
            await a.query('update memories set body=$1 where id=$2', ['Edited', memory]);
            pending = finish(b, job);
          } else if (scenario === 'withdraw-first') {
            await consent(a, owner, false); pending = finish(b, job);
          } else if (scenario === 'finish-first') {
            assert.equal((await finish(a, job)).state, 'clear');
            pending = consent(b, owner, false);
          } else if (scenario === 'budget-once') {
            assert.equal((await prepare(a, job, true)).code, 'DISPATCH_RESERVED');
            pending = prepare(b, other, true);
          } else if (scenario === 'processing-once' || scenario === 'processing-limit') {
            assert.equal((await prepare(a, job)).processing_reserved, true);
            pending = prepare(b, scenario === 'processing-once' ? job : other);
          } else {
            await a.query('select claim_account_deletion($1,$2)', [owner, ids[15]]);
            pending = finish(b, job);
          }
          // Attach rejection handling immediately while testing blocked queries.
          pending = pending.then(value => ({ value }), error => ({ error }));
          await waiting(monitor, b);
          await a.query('commit');
          const result = await pending;
          assert.ifError(result.error);
          if (scenario === 'photo-claim-once') assert.equal(result.value.code, 'PHOTO_ALREADY_CLAIMED');
          else if (['photo-withdraw-first', 'photo-delete-first'].includes(scenario)) assert.equal(result.value.code, 'SOURCE_CHANGED');
          else if (['photo-reclaim-first', 'photo-finish-once'].includes(scenario)) assert.equal(result.value.code, 'PHOTO_UNAVAILABLE');
          else if (scenario === 'photo-finish-first') assert.notEqual((await prepare(a, job, true)).code, 'DISPATCH_RESERVED');
          else if (scenario === 'claim-once') assert.equal(result.value, null);
          else if (scenario === 'budget-once') assert.equal(result.value.code, 'BUDGET_LIMIT');
          else if (scenario === 'processing-once') assert.equal(result.value.processing_reserved, true);
          else if (scenario === 'processing-limit') assert.equal(result.value.code, 'PROCESSING_BUDGET_LIMIT');
          else if (scenario !== 'finish-first') assert.equal(result.value.state, 'stale');
          if (scenario.startsWith('processing-')) {
            const counters = (await a.query('select used_bytes,used_jobs,used_images from content_safety.screening_processing_budgets')).rows;
            assert.equal(counters.length, 3);
            assert(counters.every(c => Number(c.used_bytes) === 10 && c.used_jobs === 1 && c.used_images === 1));
          }
          if (scenario !== 'claim-once') assert.equal(await clear(a), false);
        } finally {
          await a.query('rollback'); await pending;
        }
        await a.end(); await b.end(); await monitor.end(); clients.splice(0, clients.length);
        await pg.dropDatabase(name);
      });
    }
  } finally {
    for (const c of clients) await c.end().catch(() => {});
    await pg.stop();
  }
});
