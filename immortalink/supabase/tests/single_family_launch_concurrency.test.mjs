import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { singleFamilyFixture, user, familyA, familyB } from './helpers/single_family_fixture.mjs';

// PGlite is single-connection; verify interleaved transactions with real
// PostgreSQL too. Match the existing optional embedded-postgres test runner.
test('single-family admissions serialize across transactions and RPC paths', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-family-launch-pg-');
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
    const client = pg.getPgClient(name, '127.0.0.1');
    await client.connect(); clients.push(client);
    client.exec = sql => client.query(sql);
    await client.query("set statement_timeout='10s'; set lock_timeout='5s'");
    await client.query("select set_config('test.uid',$1,false)", [user]);
    return client;
  }
  async function waiting(monitor, client) {
    for (let i = 0; i < 200; i++) {
      if ((await monitor.query(
        "select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'", [client.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Second admission did not wait for the first transaction');
  }
  const direct = (client, family) => client.query(
    "insert into family_members(family_id,user_id,role) values($1,$2,'member')", [family, user]);
  const create = client => client.query("select create_family_group_and_link_vault('Concurrent family')");
  const joinA = client => client.query("select join_family_by_relationship_invite('INVITE-A')");
  const joinB = client => client.query("select join_family_by_relationship_invite('INVITE-B')");
  const legacyB = client => client.query("select join_family_by_invite('INVITE-B')");
  const scenarios = [
    ['direct admissions', client => direct(client, familyA), client => direct(client, familyB)],
    ['create versus create', create, create],
    ['create versus relationship invite', create, joinB],
    ['relationship invite versus create', joinA, create],
    ['relationship versus relationship invite', joinA, joinB],
    ['relationship versus legacy invite', joinA, legacyB],
    ['legacy versus relationship invite', client => client.query("select join_family_by_invite('INVITE-A')"), joinB],
    ['rolled-back admission releases the account', client => direct(client, familyA), client => direct(client, familyB), true],
  ];
  try {
    await pg.initialise(); await pg.start();
    for (const [index, [name, first, second, rollback]] of scenarios.entries()) {
      await t.test(name, async () => {
        const database = `family_launch_${index}`;
        await pg.createDatabase(database);
        const a = await connect(database), b = await connect(database), monitor = await connect(database);
        await singleFamilyFixture(a, { createRoles: index === 0 });
        await a.query('begin');
        try {
          await first(a);
          // Attach a handler before commit so an expected rejection is never
          // reported by node:test as an unhandled promise rejection.
          const pending = second(b).then(value => ({ value }), error => ({ error }));
          await waiting(monitor, b);
          await a.query(rollback ? 'rollback' : 'commit');
          const outcome = await pending;
          if (rollback) assert.equal(outcome.error, undefined);
          else {
            assert.equal(outcome.error?.message, 'FAMILY_MEMBERSHIP_LIMIT');
            assert.equal(outcome.error?.code, 'P0001');
          }
          assert.equal((await monitor.query('select count(*)::int as count from family_members where user_id=$1', [user])).rows[0].count, 1);
          if (!rollback) {
            assert.equal((await monitor.query("select used_at from family_invites where invite_code='INVITE-B'")).rows[0].used_at, null);
          }
        } finally { await a.query('rollback'); }
      });
    }
  } finally {
    await Promise.allSettled(clients.map(client => client.end()));
    await pg.stop();
  }
});
