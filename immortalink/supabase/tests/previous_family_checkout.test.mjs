import test from 'node:test';
import assert from 'node:assert/strict';
import {moveFixture,relocate,begin,tx,apply,move,limits,asUser,a,b,c,f,g,GB} from './helpers/contribution_move_fixture.mjs';
const ack=async(db,t,user=a)=>(await db.query('select acknowledge_owned_apple_contribution($1,$2,$3) r',[JSON.stringify(t),user,g])).rows[0].r;
async function pending(options){
 const db=await moveFixture(options);
 const first=await begin(db), old=tx(a,'same-payer',{purchaseDate:Date.now()-10000});
 await apply(db,old);await db.query('select release_family_sponsorship($1,$2)',[f,first.reservation_id]);
 old.expiresDate=Date.now()-1000;old.signedDate=Date.now();await apply(db,old,null,null,'server_notification','EXPIRED');
 await relocate(db,a,f,g);
 await db.query('select prepare_verified_apple_repurchase($1,$2,$3)',[JSON.stringify(old),g,a]);
 const hold=await begin(db,a,g);await new Promise(r=>setTimeout(r,5));
 const fresh=tx(a,'same-payer',{transactionId:'new-purchase'});
 return{db,old,hold,fresh};
}
test('notification before same-payer repurchase cannot attach it to the previous family',async()=>{
 const{db,fresh}=await pending();try{
  assert.equal((await apply(db,fresh,null,null,'server_notification','SUBSCRIBED')).code,'APPLE_REPURCHASE_AWAITING_CLIENT');
  assert.equal((await limits(db,f)).plan,'free');
  const renewal={...fresh,transactionId:'renewal-before-client',purchaseDate:fresh.purchaseDate+100,signedDate:fresh.signedDate+100,transactionReason:'RENEWAL'};
  assert.equal((await apply(db,renewal,null,null,'server_notification','DID_RENEW')).code,'APPLE_REPURCHASE_AWAITING_CLIENT');
  assert.equal((await apply(db,fresh,a,g)).applied,true);
  assert.equal((await limits(db,g)).storage_bytes,5*GB);assert.equal((await limits(db,f)).plan,'free');
  await apply(db,renewal,null,null,'server_notification','DID_RENEW');
  assert.equal((await limits(db,g)).storage_bytes,5*GB);
  await apply(db,{...renewal,signedDate:renewal.signedDate+1,revocationDate:Date.now()},null,null,'server_notification','REFUND');
  assert.equal((await limits(db,g)).plan,'free');
 }finally{await db.close()}
});
test('recovers the recorded build-41 race, clears its own fulfilled hold, and still requires confirmed move',async()=>{
 const{db,fresh,hold}=await pending();try{
  // Reproduce the previously deployed notification handler, before this patch.
  await db.query('select apply_verified_family_subscription_internal($1,null,null,$2,$3)',[JSON.stringify(fresh),'server_notification','SUBSCRIBED']);
  await assert.rejects(()=>move(db,fresh),/SPONSOR_PURCHASE_IN_PROGRESS/);
  assert.equal((await ack(db,fresh)).resolved_reservation_id,hold.reservation_id);
  assert.equal((await limits(db,f)).storage_bytes,5*GB);assert.equal((await limits(db,g)).plan,'free');
  assert.equal((await ack(db,fresh)).resolved_reservation_id,null);
  const q=await move(db,fresh);assert.equal((await limits(db,g)).plan,'free');
  assert.equal((await move(db,fresh,a,g,q.confirmation_id)).moved,true);
  assert.equal((await limits(db,g)).storage_bytes,5*GB);assert.equal((await limits(db,f)).plan,'free');
 }finally{await db.close()}
});
test('does not release a newer or different payer checkout and refuses foreign/refunded proof',async()=>{
 const{db,fresh,hold}=await pending();try{
  await db.query('select apply_verified_family_subscription_internal($1,null,null,$2,$3)',[JSON.stringify(fresh),'server_notification','SUBSCRIBED']);
  await begin(db,c,g);
  const before=(await db.query('select * from family_sponsor_reservations order by user_id')).rows;
  for(const t of [{...fresh,appAccountToken:b},{...fresh,environment:'Production'},{...fresh,revocationDate:Date.now()},{...fresh,expiresDate:Date.now()-1}])
   await assert.rejects(()=>ack(db,t),/APPLE_MOVE_UNAVAILABLE/);
  await assert.rejects(()=>ack(db,fresh,b),/APPLE_MOVE_UNAVAILABLE/);
  assert.deepEqual((await db.query('select * from family_sponsor_reservations order by user_id')).rows,before);
  await ack(db,fresh);assert.equal((await db.query('select user_id from family_sponsor_reservations')).rows[0].user_id,c);
  // An unrelated, newer hold is not evidence that this old receipt completed it.
  await db.query("insert into family_sponsor_reservations(family_id,user_id,reserved_at) values($1,$2,now()+interval '1 second')",[g,a]);
  assert.equal((await ack(db,fresh)).resolved_reservation_id,null);
  await assert.rejects(()=>move(db,fresh),/SPONSOR_PURCHASE_IN_PROGRESS/);
  await asUser(db,a);await db.exec('set role authenticated');
  await assert.rejects(()=>ack(db,fresh),/permission denied/);await db.exec('reset role;set role anon');
  await assert.rejects(()=>ack(db,fresh),/permission denied/);
 }finally{await db.close()}
});
test('real Postgres serializes notification and client checkout without duplicate or old-family grants',
 {skip:!process.env.EMBEDDED_POSTGRES_MODULE,timeout:60000},async()=>{
 const{default:EmbeddedPostgres}=await import(process.env.EMBEDDED_POSTGRES_MODULE);
 const{mkdtemp}=await import('node:fs/promises');const{randomBytes}=await import('node:crypto');const{createServer}=await import('node:net');
 const dir=await mkdtemp('/private/tmp/heiro-restore-pg-');const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 const pg=new EmbeddedPostgres({databaseDir:dir+'/data',port,user:'postgres',password:randomBytes(32).toString('hex'),persistent:false,createPostgresUser:false,postgresFlags:['-h','127.0.0.1','-k',dir],onLog:()=>{},onError:()=>{}});
 const clients=[];async function connect(){const c=pg.getPgClient('postgres','127.0.0.1');await c.connect();c.exec=s=>c.query(s);clients.push(c);await c.query("set lock_timeout='5s';set statement_timeout='10s'");return c;}
 try{
  await pg.initialise();await pg.start();const left=await connect(),right=await connect(),monitor=await connect();
  const{fresh}=await pending({db:left});
  await left.query('begin');assert.equal((await apply(left,fresh,null,null,'server_notification','SUBSCRIBED')).code,'APPLE_REPURCHASE_AWAITING_CLIENT');
  const purchase=apply(right,fresh,a,g).then(value=>({value}),error=>({error}));
  let blocked=false;
  for(let i=0;i<100;i++){if((await monitor.query("select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock'",[right.processID])).rows.length){blocked=true;break}await new Promise(r=>setTimeout(r,10))}
  assert.equal(blocked,true);await left.query('commit');const result=await purchase;assert.equal(result.error,undefined);assert.equal(result.value.applied,true);
  assert.equal((await limits(monitor,g)).storage_bytes,5*GB);assert.equal((await limits(monitor,f)).plan,'free');
  await apply(left,fresh,null,null,'server_notification','SUBSCRIBED');assert.equal((await limits(monitor,g)).storage_bytes,5*GB);
  assert.equal((await monitor.query('select count(*)::int n from apple_sponsor_reassignments')).rows[0].n,1);
 }finally{await Promise.allSettled(clients.map(c=>c.end()));await pg.stop()}
});
