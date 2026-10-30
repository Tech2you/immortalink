import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { relationshipFixture, ownerVault } from './helpers/family_relationship_fixture.mjs';
import { ownerA, user, familyA, vault } from './helpers/single_family_fixture.mjs';

test('relationship writes serialize cycles and retry receipts', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-relationships-');
  const listener = createServer();
  await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const pg = new EmbeddedPostgres({ databaseDir: `${directory}/data`, port, user: 'postgres',
    password: randomBytes(32).toString('hex'), persistent: false, createPostgresUser: false,
    postgresFlags: ['-h', '127.0.0.1', '-k', directory], onLog: () => {}, onError: () => {} });
  const clients = [];
  async function connect(database) {
    const c = pg.getPgClient(database, '127.0.0.1');
    await c.connect(); clients.push(c); c.exec = sql => c.query(sql);
    await c.query("set statement_timeout='10s'; set lock_timeout='5s'");
    return c;
  }
  async function waiting(monitor, client) {
    for (let i = 0; i < 200; i++) {
      if ((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",
        [client.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Concurrent relationship operation did not wait');
  }
  const edge = (c, parent, child) => c.query(`insert into family_relationships
    (family_id,parent_type,parent_id,child_type,child_id,relationship_kind)
    values($1,'vault',$2,'vault',$3,'parent_child')`, [familyA, parent, child]);
  try {
    await pg.initialise(); await pg.start();
    for (const [index, scenario] of ['cycle', 'rollback', 'retry'].entries()) {
      await t.test(scenario, async () => {
        const database = `relationships_${index}`;
        await pg.createDatabase(database);
        const a = await connect(database), b = await connect(database), monitor = await connect(database);
        await relationshipFixture(a, { createRoles: index === 0 });
        await a.query('insert into family_members(family_id,user_id,role) values($1,$2,$3)',
          [familyA, user, 'member']);
        await a.query("select set_config('test.uid',$1,false)", [ownerA]);
        await b.query("select set_config('test.uid',$1,false)", [ownerA]);
        await a.query('begin');
        try {
          let first, pending;
          if (scenario === 'retry') {
            const id = randomUUID();
            const request = { mode: 'legacy', name: 'Sibling', relation: 'sibling',
              anchor: { type: 'vault', id: ownerVault } };
            const create = c => c.query('select create_family_relative($1,$2,$3) result', [familyA, id, request]);
            first = (await create(a)).rows[0].result;
            pending = create(b).then(value => ({ value }), error => ({ error }));
          } else {
            await edge(a, ownerVault, vault);
            pending = edge(b, vault, ownerVault).then(value => ({ value }), error => ({ error }));
          }
          await waiting(monitor, b);
          await a.query(scenario === 'rollback' ? 'rollback' : 'commit');
          const result = await pending;
          if (scenario === 'cycle') assert.equal(result.error?.message, 'RELATIONSHIP_ANCESTRY_CYCLE');
          else assert.equal(result.error, undefined);
          if (scenario === 'retry') {
            assert.deepEqual(result.value.rows[0].result, first);
            assert.equal((await monitor.query('select count(*)::int n from legacy_family_members')).rows[0].n, 1);
            assert.equal((await monitor.query('select count(*)::int n from family_access.relationship_requests')).rows[0].n, 1);
          }
          assert.equal((await monitor.query('select count(*)::int n from family_relationships')).rows[0].n, 1);
        } finally { await a.query('rollback'); }
      });
    }
  } finally {
    for (const c of clients) await c.end();
    await pg.stop();
  }
});
