import {test} from 'node:test';import assert from 'node:assert/strict';import {mkdtemp} from 'node:fs/promises';import {randomBytes} from 'node:crypto';import {createServer} from 'node:net';
import {setup} from './helpers/media_backup_fixture.mjs';
test('parallel backup claims and capacity reservations serialize',{skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:120000},async()=>{
 const {default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
 const directory=await mkdtemp('/private/tmp/heiro-backup-pg-');const listener=createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));const port=listener.address().port;await new Promise(r=>listener.close(r));
 const pg=new EmbeddedPostgres({databaseDir:directory+'/data',port,user:'postgres',password:randomBytes(32).toString('hex'),persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',directory],onLog:()=>{},onError:()=>{}});const clients=[];
 try {await pg.initialise();await pg.start();for(let i=0;i<20;i++){const c=pg.getPgClient('postgres','127.0.0.1');await c.connect();c.exec=s=>c.query(s);clients.push(c);}const db=clients[0];await setup(db);
  await db.query('update media_backup.control set enabled=true,max_daily_copy_bytes=1000');
  const dispatch=await Promise.all(clients.map(c=>c.query('select dispatch_media_backup() value')));assert.equal(dispatch.filter(r=>r.rows[0].value).length,1);
  const token=(await db.query('select headers from net.requests')).rows[0].headers['x-backup-run-token'];
  const claims=await Promise.all(clients.map(c=>c.query('select claim_media_backup_run($1) value',[token])));assert.equal(claims.filter(r=>r.rows[0].value).length,1);
  await db.query("insert into storage.objects select gen_random_uuid(),'memory_photos','generated/'||n,'v1',now(),'{\"size\":100}',null,false from generate_series(1,20) n");
  const jobs=await Promise.all(clients.map(c=>c.query('select next_media_backup_work($1) value',[token])));assert.equal(jobs.filter(r=>r.rows[0].value).length,10);
  assert.equal(new Set(jobs.filter(r=>r.rows[0].value).map(r=>r.rows[0].value.fingerprint)).size,10);
  assert.equal((await db.query('select copy_bytes from media_backup.control')).rows[0].copy_bytes,'1000');
 }finally{await Promise.all(clients.map(c=>c.end()));await pg.stop().catch(()=>{});}
});
