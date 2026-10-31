import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {fixture,a,b,f,begin,tx,apply,limits,GB} from './helpers/family_contributions_fixture.mjs';

test('simultaneous verified payments and refunds serialize without lost or duplicate contributions',{
 skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000},async()=>{
 const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
 const directory=await mkdtemp('/private/tmp/heiro-buckets-pg-');
 const listener=createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));
 const port=listener.address().port;await new Promise(r=>listener.close(r));
 const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),persistent:false,
  createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
 const clients=[];
 async function connect(){const c=pg.getPgClient('postgres','127.0.0.1');await c.connect();c.exec=s=>c.query(s);clients.push(c);await c.query("set statement_timeout='10s';set lock_timeout='5s'");return c;}
 async function waiting(monitor,client){for(let i=0;i<150;i++){if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[client.processID])).rows.length)return;await delay(10);}assert.fail('Expected write to wait for family lock');}
 try {
  await pg.initialise();await pg.start();const left=await connect(),right=await connect(),monitor=await connect();await fixture({db:left});
  await Promise.all([begin(left,a),begin(right,b)]);const ta=tx(),tb=tx(b);
  await left.query('begin');await apply(left,ta);
  const pending=apply(right,tb,b).then(value=>({value}),error=>({error}));await waiting(monitor,right);await left.query('commit');
  assert.equal((await pending).error,undefined);assert.equal((await limits(monitor)).storage_bytes,10*GB);
  await Promise.all([apply(left,ta),apply(right,tb,b)]);assert.equal((await limits(monitor)).storage_bytes,10*GB);
  await left.query('begin');await apply(left,{...ta,signedDate:ta.signedDate+1000,revocationDate:Date.now()},null,null,'server_notification','REFUND');
  const renewal=apply(right,{...tb,transactionId:'renewed',purchaseDate:tb.purchaseDate+1000,signedDate:tb.signedDate+1000},null,null,'server_notification').then(value=>({value}),error=>({error}));
  await waiting(monitor,right);await left.query('commit');assert.equal((await renewal).error,undefined);assert.equal((await limits(monitor)).storage_bytes,5*GB);
  assert.equal((await monitor.query('select count(*)::int n from family_entitlements where family_id=$1',[f])).rows[0].n,2);
 } finally {await Promise.allSettled(clients.map(c=>c.end()));await pg.stop();}
});
