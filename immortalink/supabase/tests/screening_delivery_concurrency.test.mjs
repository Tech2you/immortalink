import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {deliveryFixture,issue,claimDelivery,authorize,leased,finishDelivery,health} from './helpers/delivery_fixture.mjs';
import {flagged,inspected,decide} from './helpers/screening_review_fixture.mjs';
import {memory,legacyMemory,report,act} from './helpers/retirement_fixture.mjs';

test('real PostgreSQL serializes delivery claims, budgets, edits and report restrictions',{
  skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000,
},async t=>{
  const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory=await mkdtemp('/private/tmp/heiro-delivery-pg-');
  const listener=createServer();await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
  const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
  const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),
    persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
  const clients=[];
  async function connect(name){const c=pg.getPgClient(name,'127.0.0.1');await c.connect();clients.push(c);c.exec=sql=>c.query(sql);
    await c.query("set statement_timeout='10s';set lock_timeout='5s'");return c;}
  async function waiting(monitor,c){
    for(let i=0;i<200;i++){
      if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[c.processID])).rows.length)return;
      await delay(10);
    }assert.fail('Concurrent operation did not wait for the lifecycle lock');
  }
  try{
    await pg.initialise();await pg.start();
    for(const [i,scenario] of ['issue-once','claim-once','authorize-once','finish-once','edit-first','hide-first','one-budget','unknown-token'].entries())await t.test(scenario,async()=>{
      const name=`delivery_${i}`;await pg.createDatabase(name);const a=await connect(name),b=await connect(name),monitor=await connect(name);
      await deliveryFixture(a);const caseId=await flagged(a);
      let token,job,push,other,reportId;
      if(scenario==='claim-once')token=await issue(a);
      if(['authorize-once','finish-once','one-budget'].includes(scenario))job=await leased(a);
      if(scenario==='finish-once')await authorize(a,job);
      if(['edit-first','hide-first'].includes(scenario)){
        const data=await inspected(a,caseId);await decide(a,caseId,data.revision);push=await leased(a,'push');
        if(scenario==='hide-first')reportId=await report(a);
      }
      if(scenario==='one-budget'){
        await a.exec('update content_safety.screening_delivery_config set email_daily_limit=1');
        await flagged(a,'legacy_memory',legacyMemory);other=await leased(a);
      }
      let pending;await a.query('begin');
      try{
        if(scenario==='issue-once'){assert.ok(await issue(a));pending=issue(b);}
        if(scenario==='claim-once'){assert.ok(await claimDelivery(a,token));pending=claimDelivery(b,token);}
        if(scenario==='authorize-once'){assert.ok(await authorize(a,job));pending=authorize(b,job);}
        if(scenario==='finish-once'){assert.equal(await finishDelivery(a,job),true);pending=finishDelivery(b,job);}
        if(scenario==='edit-first'){await a.query("update memories set body='Changed before dispatch' where id=$1",[memory]);pending=authorize(b,push);}
        if(scenario==='hide-first'){await act(a,reportId,'hide');pending=authorize(b,push);}
        if(scenario==='one-budget'){
          assert.ok(await authorize(a,job));pending=authorize(b,other);
        }
        if(scenario==='unknown-token'){
          await a.query('select content_safety.media_lifecycle_lock()');pending=claimDelivery(b,'f'.repeat(64));
        }
        pending=pending.then(value=>({value}),error=>({error}));
        if(scenario==='unknown-token')assert.match((await pending).error?.message??'',/UNAUTHORIZED/);
        else await waiting(monitor,b);
        await a.query('commit');const result=await pending;
        if(scenario==='claim-once'||scenario==='unknown-token')assert.match(result.error?.message??'',/UNAUTHORIZED/);
        else {assert.ifError(result.error);assert.equal(result.value,scenario==='finish-once'?false:null);}
        if(scenario==='authorize-once'||scenario==='one-budget')assert.equal((await health(monitor)).email_attempts,1);
        if(scenario==='edit-first'||scenario==='hide-first')assert.equal((await health(monitor)).push_attempts,0);
      }finally{await a.query('rollback');await pending;}
      for(const c of clients.splice(0))await c.end();await pg.dropDatabase(name);
    });
  }finally{for(const c of clients)await c.end().catch(()=>{});await pg.stop();}
});
