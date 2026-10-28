import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {reviewFixture,flagged,inspected,decide} from './helpers/screening_review_fixture.mjs';
import {asUser} from './helpers/publication_fixture.mjs';
import {memory,viewer,photoPath,report,act} from './helpers/retirement_fixture.mjs';

test('real PostgreSQL serializes human approval with edits, restrictions, deletion and another reviewer',{
  skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000,
},async t=>{
  const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory=await mkdtemp('/private/tmp/heiro-human-review-pg-');
  const listener=createServer();await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
  const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
  const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),
    persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
  const clients=[];
  async function connect(name){
    const c=pg.getPgClient(name,'127.0.0.1');await c.connect();clients.push(c);
    c.exec=sql=>c.query(sql);await c.query("set statement_timeout='10s';set lock_timeout='5s'");return c;
  }
  async function waiting(monitor,c){
    for(let i=0;i<200;i++){
      if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[c.processID])).rows.length)return;
      await delay(10);
    }
    assert.fail('Concurrent operation did not wait for the lifecycle lock');
  }
  try{
    await pg.initialise();await pg.start();
    for(const [i,scenario] of ['edit-first','approve-first','bytes-first','hide-first','delete-first','two-approvals'].entries()){
      await t.test(scenario,async()=>{
        const name=`human_review_${i}`;await pg.createDatabase(name);
        const a=await connect(name),b=await connect(name),monitor=await connect(name);
        await reviewFixture(a);const id=await flagged(a),data=await inspected(a,id);
        const other=await inspected(a,id,'Other reviewer');
        const reportId=scenario==='hide-first'?await report(a):null;
        let pending;await a.query('begin');
        try{
          if(scenario==='approve-first'||scenario==='two-approvals'){
            assert.equal((await decide(a,id,data.revision)).status,'approved');
            pending=scenario==='approve-first'?b.query("update memories set body='Changed after approval' where id=$1",[memory]):
              decide(b,id,other.revision,'approve','Other reviewer');
          }else{
            if(scenario==='edit-first')await a.query("update memories set body='Changed before approval' where id=$1",[memory]);
            if(scenario==='bytes-first')await a.query(`update storage.objects set metadata=jsonb_set(metadata,'{eTag}','"new-bytes"') where name=$1`,[photoPath]);
            if(scenario==='hide-first')await act(a,reportId,'hide');
            if(scenario==='delete-first')await a.query('delete from memories where id=$1',[memory]);
            pending=decide(b,id,data.revision);
          }
          pending=pending.then(value=>({value}),error=>({error}));await waiting(monitor,b);
          await a.query('commit');const result=await pending;
          if(scenario==='approve-first')assert.ifError(result.error);
          else assert.match(result.error?.message||'',/SAFETY_CASE_CHANGED/);
          const visible=scenario==='two-approvals'?1:0;
          assert.equal((await asUser(monitor,viewer,'select id from memories where id=$1',[memory])).rows.length,visible);
          assert.equal((await asUser(monitor,viewer,'select id from storage.objects where name=$1',[photoPath])).rows.length,visible);
          assert.equal(Number((await monitor.query("select count(*) from content_safety.screening_review_events where action='approve'")).rows[0].count),
            ['approve-first','two-approvals'].includes(scenario)?1:0);
        }finally{await a.query('rollback');await pending;}
        for(const c of clients.splice(0))await c.end();await pg.dropDatabase(name);
      });
    }
  }finally{for(const c of clients)await c.end().catch(()=>{});await pg.stop();}
});
