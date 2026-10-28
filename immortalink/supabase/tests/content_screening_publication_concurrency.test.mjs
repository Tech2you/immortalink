import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { publicationFixture, dispatched, asUser } from './helpers/publication_fixture.mjs';
import { finish } from './helpers/screening_fixture.mjs';
import { memory, viewer, photoPath } from './helpers/retirement_fixture.mjs';

test('real PostgreSQL serializes publication with edits, media replacement and source deletion', {
  skip: !process.env.EMBEDDED_POSTGRES_MODULE, timeout:120000,
}, async t => {
  const { default: EmbeddedPostgres } = await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory = await mkdtemp('/private/tmp/heiro-publication-pg-');
  const listener = createServer(); await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
  const port = listener.address().port; await new Promise(resolve=>listener.close(resolve));
  const pg = new EmbeddedPostgres({ databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),
    persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{} });
  const clients=[];
  async function connect(name) {
    const c=pg.getPgClient(name,'127.0.0.1'); await c.connect(); clients.push(c);
    c.exec=sql=>c.query(sql); await c.query("set statement_timeout='10s'; set lock_timeout='5s'"); return c;
  }
  async function waiting(monitor,c) {
    for(let i=0;i<200;i++) {
      if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[c.processID])).rows.length) return;
      await delay(10);
    }
    assert.fail('Second operation did not wait for the publication lock');
  }
  try {
    await pg.initialise(); await pg.start();
    for(const [i,scenario] of ['edit-first','finish-first','bytes-first','delete-first','pause-first'].entries()) {
      await t.test(scenario,async()=>{
        const name=`publication_${i}`; await pg.createDatabase(name);
        const a=await connect(name),b=await connect(name),monitor=await connect(name);
        await publicationFixture(a); const job=await dispatched(a); let pending;
        await a.query('begin');
        try {
          if(scenario==='finish-first') {
            assert.equal((await finish(a,job)).state,'clear');
            pending=b.query("update memories set body='Changed' where id=$1",[memory]);
          } else {
            if(scenario==='edit-first') await a.query("update memories set body='Changed' where id=$1",[memory]);
            if(scenario==='bytes-first') await a.query(`update storage.objects set metadata=jsonb_set(metadata,'{eTag}','"changed"') where name=$1`,[photoPath]);
            if(scenario==='delete-first') await a.query('delete from memories where id=$1',[memory]);
            if(scenario==='pause-first') await a.query('update content_safety.screening_controls set enabled=false');
            pending=finish(b,job);
          }
          pending=pending.then(value=>({value}),error=>({error})); await waiting(monitor,b);
          await a.query('commit'); const result=await pending; assert.ifError(result.error);
          assert.equal((await asUser(monitor,viewer,'select id from memories where id=$1',[memory])).rows.length,0);
          assert.equal((await asUser(monitor,viewer,'select id from storage.objects where name=$1',[photoPath])).rows.length,0);
          if(scenario!=='finish-first' && scenario!=='delete-first') assert.equal(result.value.state,'stale');
        } finally { await a.query('rollback'); await pending; }
        for(const c of clients.splice(0)) await c.end(); await pg.dropDatabase(name);
      });
    }
  } finally { for(const c of clients) await c.end().catch(()=>{}); await pg.stop(); }
});
