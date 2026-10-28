import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {fixture,report,act,next,move,owner,lease} from './helpers/retirement_fixture.mjs';

test('real PostgreSQL serializes retirement with deletion and restore',{
  skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:90000,
},async(t)=>{
  const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory=await mkdtemp('/private/tmp/heiro-retirement-pg-');
  const listener=createServer();
  await new Promise(resolve=>listener.listen(0,'127.0.0.1',resolve));
  const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
  const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),
    persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
  const clients=[];
  const connect=async(name)=>{const c=pg.getPgClient(name,'127.0.0.1');await c.connect();clients.push(c);
    await c.query("set statement_timeout='10s';set lock_timeout='5s'");
    c.exec=(sql)=>c.query(sql);return c;};
  async function waiting(monitor,client){
    for(let i=0;i<200;i++){
      const rows=(await monitor.query("select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted",[client.processID])).rows;
      if(rows.length)return;await delay(10);
    }
    assert.fail('Second connection did not wait on the lifecycle lock');
  }
  try{
    await pg.initialise();await pg.start();
    for(const [index,scenario] of ['delete-first','move-first','restore-during-move'].entries()){
      await t.test(scenario,async()=>{
        const name=`qa_${index}`;await pg.createDatabase(name);
        const a=await connect(name),b=await connect(name),monitor=await connect(name);
        await fixture(a);const id=await report(a,'legacy_memory');await act(a,id,'hide');
        // Finish the second attachment first so the restore case isolates the in-flight move.
        const first=await next(a,id);await move(a,first);const job=await next(a,id);
        const preview=(await a.query("select preview_content_report($1,'QA') data",[id])).rows[0].data;
        await a.query('begin');
        let pending;
        try{
          if(scenario==='delete-first'){
            await a.query('select claim_account_deletion($1,$2)',[owner,lease]);
            pending=move(b,job).then(()=>({ok:true}),error=>({error}));
          }else{
            await move(a,job);
            pending=(scenario==='move-first'?b.query('select claim_account_deletion($1,$2)',[owner,lease]):
              b.query("select review_content_report_checked($1,'restore','QA','QA',$2)",[id,preview.revision]))
              .then(()=>({ok:true}),error=>({error}));
          }
          await waiting(monitor,b);await a.query('commit');const result=await pending;
          if(scenario==='delete-first')assert.match(result.error?.message||'',/SAFETY_MEDIA_ADDRESS_RESERVED/);
          if(scenario==='restore-during-move')assert.match(result.error?.message||'',/SAFETY_CASE_CHANGED/);
          if(scenario==='move-first'){
            assert.equal(result.ok,true);
            assert.equal((await b.query('select count(*)::int n from account_deletion_files where source_path=$1',[job.source])).rows[0].n,0);
            assert.equal((await b.query('select count(*)::int n from account_deletion_files where source_path=$1 and target_path is not null',[job.destination])).rows[0].n,1);
          }
        }finally{await a.query('rollback');await pending;}
        await a.end();await b.end();await monitor.end();clients.splice(0,clients.length);
        await pg.dropDatabase(name);
      });
    }
  }finally{for(const c of clients)await c.end().catch(()=>{});await pg.stop();}
});
