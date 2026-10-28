import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { sharingFixture, request, consent } from './helpers/screening_fixture.mjs';
import { owner, memory, vault, ids } from './helpers/retirement_fixture.mjs';

test('real PostgreSQL serializes sharing requests with consent, deletion and activation', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-sharing-pg-');
  const listener = createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const pg = new EmbeddedPostgres({ databaseDir: `${directory}/data`, port, user: 'postgres',
    password: randomBytes(32).toString('hex'), persistent: false, createPostgresUser: false,
    postgresFlags: ['-h', '127.0.0.1', '-k', directory], onLog: () => {}, onError: () => {} });
  const clients = [];
  async function connect(name) {
    const c = pg.getPgClient(name, '127.0.0.1'); await c.connect(); clients.push(c);
    c.exec = sql => c.query(sql);
    await c.query("set statement_timeout='10s'; set lock_timeout='5s'"); return c;
  }
  async function waiting(monitor, client) {
    for (let i = 0; i < 200; i++) {
      if ((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'", [client.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Concurrent operation did not wait on the tested lock');
  }
  try {
    await pg.initialise(); await pg.start();
    for (const [index, scenario] of ['request-once', 'archive-edit-first', 'delete-first', 'withdraw-first',
      'request-first-delete', 'activate-first-insert', 'disable-first-insert'].entries()) {
      await t.test(scenario, async () => {
        const name = `sharing_${index}`; await pg.createDatabase(name);
        const a = await connect(name), b = await connect(name), monitor = await connect(name);
        await sharingFixture(a, { enabled: scenario !== 'activate-first-insert', fresh: scenario !== 'archive-edit-first' });
        let pending, first;
        await a.query('begin');
        try {
          if (scenario === 'request-once' || scenario === 'request-first-delete') {
            first = await request(a); assert.equal(first.state, 'queued');
            pending = scenario === 'request-once' ? request(b) : b.query('delete from memories where id=$1', [memory]);
          } else if (scenario === 'archive-edit-first') {
            await a.query("update memories set created_at=now()+interval '1 year',share_to_family_feed=true where id=$1", [memory]);
            pending = request(b);
          } else if (scenario === 'delete-first') {
            await a.query('delete from memories where id=$1', [memory]); pending = request(b);
          } else if (scenario === 'withdraw-first') {
            await consent(a, owner, false); pending = request(b);
          } else {
            await a.query("update content_safety.screening_controls set enabled=$1,eligible_after=now()-interval '1 minute'", [scenario === 'activate-first-insert']);
            pending = b.query("insert into memories(id,vault_id,body) values($1,$2,'New fixture')", [ids[18], vault]);
          }
          pending = pending.then(value => ({ value }), error => ({ error }));
          await waiting(monitor, b);
          await a.query('commit');
          const result = await pending; assert.ifError(result.error);
          const jobs = (await a.query('select * from content_safety.screening_jobs')).rows;
          if (scenario === 'request-once') { assert.deepEqual(result.value, first); assert.equal(jobs.length, 1); }
          else {
            assert.equal(jobs.length, 0);
            if (scenario === 'withdraw-first') assert.equal(result.value.code, 'PERMISSION_REQUIRED');
            if (['delete-first', 'archive-edit-first'].includes(scenario)) assert.equal(result.value.code, 'REQUEST_UNAVAILABLE');
            if (scenario.endsWith('first-insert')) {
              const origins = (await a.query('select * from content_safety.screening_origins where memory_id=$1', [ids[18]])).rows;
              // Pausing the processor after capture starts still records new work.
              assert.equal(origins.length, 1);
            }
          }
        } finally { await a.query('rollback'); await pending; }
        await a.end(); await b.end(); await monitor.end(); clients.splice(0, clients.length);
        await pg.dropDatabase(name);
      });
    }
  } finally {
    for (const c of clients) await c.end().catch(() => {});
    await pg.stop();
  }
});
