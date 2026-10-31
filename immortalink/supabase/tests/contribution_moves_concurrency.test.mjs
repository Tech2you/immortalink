import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {paidMoveFixture,move,used,usage,begin,tx,apply,asUser,a,b,f,g,limits,GB} from './helpers/contribution_move_fixture.mjs';
test('real Postgres serializes usage, duplicate confirmation and refund with a move',{skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000},async()=>{
 const{default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
 const directory=await mkdtemp('/private/tmp/heiro-move-pg-');const listener=createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));const port=listener.address().port;await new Promise(r=>listener.close(r));
 const pg=new EmbeddedPostgres({databaseDir:`${directory}/data`,port,user:'postgres',password:randomBytes(32).toString('hex'),persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});
 const clients=[];async function connect(){const c=pg.getPgClient('postgres','127.0.0.1');await c.connect();c.exec=s=>c.query(s);clients.push(c);await c.query("set statement_timeout='10s';set lock_timeout='5s'");return c;}
 async function waiting(monitor,c){for(let i=0;i<150;i++){if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[c.processID])).rows.length)return;await delay(10)}assert.fail('operation did not wait for the move lock')}
 const settle=p=>p.then(value=>({value}),error=>({error}));
 try{
  await pg.initialise();await pg.start();const left=await connect(),right=await connect(),monitor=await connect();const{t}=await paidMoveFixture({db:left});await begin(left,b);await apply(left,tx(b),b);await used(left,f,200,1000);
  let q=await move(left,t);await asUser(left,b);await left.query('begin');await left.query('select everroot_consume_ai_usage($1,null,1)',[f]);
  let pending=settle(move(right,t,a,g,q.confirmation_id));await waiting(monitor,right);await left.query('commit');assert.match((await pending).error.message,/APPLE_MOVE_STALE/);
  q=await move(left,t);await left.query('begin');await move(left,t,a,g,q.confirmation_id);
  pending=settle(move(right,t,a,g,q.confirmation_id));await waiting(monitor,right);await left.query('commit');assert.equal((await pending).value.moved,true);
  assert.deepEqual(await usage(monitor,g),{ai:101,seconds:500});assert.deepEqual(await usage(monitor,f),{ai:100,seconds:500});assert.equal((await monitor.query('select count(*)::int n from heiro_billing.contribution_moves')).rows[0].n,1);
  await asUser(left,a);await left.query('begin');await left.query('select everroot_consume_ai_usage($1,null,1)',[g]);
  pending=settle(apply(right,{...t,signedDate:t.signedDate+1000,revocationDate:Date.now()},null,null,'server_notification','REFUND'));await waiting(monitor,right);await left.query('commit');assert.equal((await pending).error,undefined);
  assert.equal((await limits(monitor,g)).plan,'free');assert.equal((await limits(monitor,f)).storage_bytes,5*GB);
 }finally{await Promise.allSettled(clients.map(c=>c.end()));await pg.stop()}
});
