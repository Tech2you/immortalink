import {test} from 'node:test';import assert from 'node:assert/strict';import {mkdtemp} from 'node:fs/promises';import {randomBytes} from 'node:crypto';import {createServer} from 'node:net';
import {setup,index} from './helpers/launch_security_fixture.mjs';
test('AI reservations, settlements and index replacement serialize across real database connections',{skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000},async t=>{
 const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
 const directory=await mkdtemp('/private/tmp/heiro-launch-security-pg-');const listener=createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));const port=listener.address().port;await new Promise(r=>listener.close(r));
 const pg=new EmbeddedPostgres({databaseDir:directory+'/data',port,user:'postgres',password:randomBytes(32).toString('hex'),persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});const clients=[];
 try {await pg.initialise();await pg.start();for(let i=0;i<25;i++){const c=pg.getPgClient('postgres','127.0.0.1');await c.connect();c.exec=sql=>c.query(sql);clients.push(c);}const db=clients[0];await setup(db);
 await t.test('25 simultaneous requests admit only 20 within US$2',async()=>{
  const results=await Promise.all(clients.map(c=>c.query("select reserve_ai_budget('chat',100000) id")));
  assert.equal(results.filter(r=>r.rows[0].id).length,20);
  assert.equal((await db.query('select reserved_microdollars n from heiro_security.ai_budget_days')).rows[0].n,2000000);
 });
 await t.test('duplicate concurrent settlement refunds once only',async()=>{
  const id=(await db.query('select id from heiro_security.ai_budget_reservations limit 1')).rows[0].id;
  await Promise.all(clients.map(c=>c.query('select settle_ai_budget($1,10000)',[id])));
  assert.equal((await db.query('select reserved_microdollars n from heiro_security.ai_budget_days')).rows[0].n,1910000);
 });
 await t.test('simultaneous refreshes build once and retain one complete index',async()=>{
  const results=await Promise.all(clients.map(index));assert.equal(results.filter(r=>!r.rows[0].result.unchanged).length,1);
  assert.equal((await db.query('select count(*) n from memory_chunks')).rows[0].n,'1');
  assert.equal((await db.query('select day_count n from heiro_security.index_rate')).rows[0].n,1);
 });
 }finally{await Promise.all(clients.map(c=>c.end()));await pg.stop().catch(()=>{});}
});
