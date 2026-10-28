import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { randomBytes,randomUUID } from 'node:crypto';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import {notificationFixture,claim,actor,other,family,vault,memory} from './helpers/notification_guard_fixture.mjs';
test('notification replay and hourly limits serialize concurrent claims',{
  skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000,
},async t=>{
  const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
  const directory=await mkdtemp('/private/tmp/heiro-push-pg-');
  const listener=createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));
  const port=listener.address().port;await new Promise(r=>listener.close(r));
  const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),
    persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
  const clients=[];
  async function connect(name){const c=pg.getPgClient(name,'127.0.0.1');await c.connect();clients.push(c);c.exec=sql=>c.query(sql);
    await c.query("set statement_timeout='10s'; set lock_timeout='5s'");return c;}
  try{
    await pg.initialise();await pg.start();
    for(const [i,scenario] of [
      {name:'duplicate event',code:'DUPLICATE'},
      {name:'sender hourly cap',count:19,code:'RATE_LIMIT'},
      {name:'family hourly cap',count:49,seedActor:other,code:'RATE_LIMIT'},
      {name:'rollback releases claim',rollback:true},
    ].entries())await t.test(scenario.name,async()=>{
      const name=`push_${i}`;await pg.createDatabase(name);
      const a=await connect(name),b=await connect(name),monitor=await connect(name);
      await notificationFixture(a,{roles:i===0});
      const target=scenario.count?randomUUID():memory;
      if(scenario.count){
        await a.query('insert into memories(id,vault_id) values($1,$2)',[target,vault]);
        await a.query("insert into notification_guard.claims select 'seed-'||g,$1,$2,now() from generate_series(1,$3::int) g",[family,scenario.seedActor??actor,scenario.count]);
      }
      await a.query('begin');
      try{
        assert.equal((await claim(a)).allowed,true);
        const pending=claim(b,{target}).then(value=>({value}),error=>({error}));
        let waiting=false;
        for(let j=0;j<200;j++){
          if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[b.processID])).rows.length){waiting=true;break;}
          await delay(10);
        }
        assert(waiting,'second claim must wait for first transaction');
        await a.query(scenario.rollback?'rollback':'commit');
        const result=await pending;assert.equal(result.error,undefined);
        if(scenario.rollback)assert.equal(result.value.allowed,true);else assert.equal(result.value.code,scenario.code);
      }finally{await a.query('rollback');}
    });
  }finally{await Promise.allSettled(clients.map(c=>c.end()));await pg.stop();}
});
