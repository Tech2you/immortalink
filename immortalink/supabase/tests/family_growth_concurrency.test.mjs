import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { growthFixture, installStorageQuota, setBytes } from './helpers/family_growth_fixture.mjs';
import { user, ownerA, ownerB, familyA, vault } from './helpers/single_family_fixture.mjs';

test('family growth limits serialize against concurrent invitations, joins and uploads', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout: 120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-growth-pg-');
  const listener = createServer();
  await new Promise(resolve => listener.listen(0,'127.0.0.1',resolve));
  const port = listener.address().port;
  await new Promise(resolve => listener.close(resolve));
  const pg = new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',
    password:randomBytes(32).toString('hex'),persistent:false,createPostgresUser:false,
    postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
  const clients=[];
  async function connect(database) {
    const c=pg.getPgClient(database,'127.0.0.1');
    await c.connect(); clients.push(c); c.exec=sql=>c.query(sql);
    await c.query("set statement_timeout='10s'; set lock_timeout='5s'");
    return c;
  }
  async function waiting(monitor,client) {
    for(let i=0;i<200;i++) {
      if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[client.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Concurrent write did not wait for the quota transaction');
  }
  const invite=(c,actor=ownerA)=>c.query(`insert into family_invites(family_id,created_by,invite_code,expires_at)
    values($1,$2,$3,now()+interval '1 day')`,[familyA,actor,randomUUID()]);
  const upload=c=>c.query('insert into storage.objects values($1,$2,$3)',
    ['memory_photos',`${ownerA}/${familyA}/${randomUUID()}.jpg`,JSON.stringify({size:1})]);
  const join=async c=>{
    await c.query("select set_config('test.uid',$1,false)",[user]);
    return c.query("select join_family_by_relationship_invite('JOIN')");
  };
  const legacy=c=>c.query('insert into legacy_family_members(family_id) values($1)',[familyA]);
  const scenarios=[
    {name:'sender hourly cap',setup:async c=>{
      await c.query(`insert into family_access.invite_rate_events
        select gen_random_uuid(),$1,$2,now()-interval '1 minute' from generate_series(1,19)`,[familyA,ownerA]);
    },first:c=>invite(c),second:c=>invite(c),code:'ERR_EVERROOT_INVITE_RATE_LIMIT',age:true},
    {name:'family hourly cap across senders',setup:async c=>{
      await c.query(`insert into family_access.invite_rate_events
        select gen_random_uuid(),$1,gen_random_uuid(),now()-interval '1 minute' from generate_series(1,49)`,[familyA]);
    },first:c=>invite(c),second:c=>invite(c,ownerB),code:'ERR_EVERROOT_INVITE_RATE_LIMIT'},
    {name:'pending invite cap',setup:async c=>{
      for(let i=0;i<9;i++) await invite(c,randomUUID());
    },first:c=>invite(c),second:c=>invite(c,ownerB),code:'ERR_EVERROOT_PENDING_INVITE_LIMIT'},
    {name:'legacy profile cap',setup:async c=>{
      for(let i=0;i<7;i++) await legacy(c);
    },first:legacy,second:legacy,code:'ERR_EVERROOT_LEGACY_LIMIT'},
    {name:'upload fills storage before invite acceptance',storage:true,
      first:upload,second:join,code:'ERR_EVERROOT_STORAGE_LIMIT'},
    {name:'joining member brings media before concurrent upload',storage:true,incoming:true,
      first:join,second:upload,code:'ERR_EVERROOT_STORAGE_LIMIT'},
    {name:'rolled back upload does not block admission',storage:true,
      first:upload,second:join,rollback:true},
  ];
  try {
    await pg.initialise(); await pg.start();
    for(const [index,s] of scenarios.entries()) {
      await t.test(s.name,async()=>{
        const database=`growth_${index}`;
        await pg.createDatabase(database);
        const a=await connect(database),b=await connect(database),monitor=await connect(database);
        await growthFixture(a,{createRoles:index===0});
        if(s.storage) {
          await a.query(`insert into family_invites(family_id,created_by,invite_code,expires_at)
            values($1,$2,'JOIN',now()+interval '1 day')`,[familyA,ownerA]);
          await setBytes(a,524288000-1);
          if(s.incoming) await a.query('insert into storage.objects values($1,$2,$3)',
            ['memory_photos',`${user}/${vault}/existing.jpg`,JSON.stringify({size:1})]);
          await installStorageQuota(a);
        }
        if(s.setup) await s.setup(a);
        await a.query('begin');
        try {
          await s.first(a);
          if(s.age) await a.query("update family_access.invite_rate_events set created_at=now()-interval '1 minute'");
          const pending=s.second(b).then(value=>({value}),error=>({error}));
          await waiting(monitor,b);
          await a.query(s.rollback?'rollback':'commit');
          const outcome=await pending;
          if(s.rollback) assert.equal(outcome.error,undefined);
          else assert.equal(outcome.error?.detail || outcome.error?.message,s.code);
          if(s.storage) {
            const usage=Number((await monitor.query('select everroot_storage_bytes_used($1,null) as used',[familyA])).rows[0].used);
            assert.ok(usage<=524288000);
          }
        } finally {await a.query('rollback');}
      });
    }
  } finally {
    await Promise.allSettled(clients.map(c=>c.end()));
    await pg.stop();
  }
});
