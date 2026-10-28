import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { notificationFixture,claim,actor,recipient,other,family,vault,memory,outsider } from './helpers/notification_guard_fixture.mjs';
const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
async function run(fn){const db=new PGlite();try{await notificationFixture(db);await fn(db);}finally{await db.close();}}
const nextMemory=async(db)=>{const id=randomUUID();await db.query('insert into memories(id,vault_id) values($1,$2)',[id,vault]);return id;};
test('only trusted server can claim or inspect the notification ledger',()=>run(async db=>{
  for(const role of ['anon','authenticated']) {
    await db.exec(`set role ${role}`);
    await assert.rejects(claim(db),e=>e.code==='42501');
    await assert.rejects(db.exec('select * from notification_guard.claims'),e=>e.code==='42501');
    await db.exec('reset role');
  }
  await db.exec('set role service_role');
  assert.equal((await claim(db)).allowed,true);
  await assert.rejects(db.exec('delete from notification_guard.claims'),e=>e.code==='42501');
}));
test('one event per memory even after timestamp changes; welcome is per membership',()=>run(async db=>{
  assert.deepEqual(await claim(db),{allowed:true,family_id:family,recipient_ids:[recipient,other]});
  assert.equal((await claim(db)).code,'DUPLICATE');
  await db.exec("update memories set created_at=now()+interval '30 seconds'");
  assert.equal((await claim(db)).code,'DUPLICATE');
  assert.equal((await claim(db,{type:'family_joined',target:family})).allowed,true);
  assert.equal((await claim(db,{type:'family_joined',target:family})).code,'DUPLICATE');
}));
test('outsiders, other authors, private and stale events cannot dispatch',()=>run(async db=>{
  for(const args of [{user:outsider},{user:recipient},{user:randomUUID()},{target:randomUUID()},{type:'bad'},
    {type:'family_joined',target:family,user:outsider}])assert.equal((await claim(db,args)).code,'DENIED');
  await db.exec('update memories set share_to_family_feed=false');
  assert.equal((await claim(db)).code,'DENIED');
  await db.exec("update memories set share_to_family_feed=true,created_at=now()-interval '25 hours'");
  assert.equal((await claim(db)).code,'DENIED');
  await db.exec("update memories set created_at=now()+interval '2 minutes'");
  assert.equal((await claim(db)).code,'DENIED');
  await db.exec("update memories set created_at=now(); delete from family_members where user_id='"+actor+"'");
  assert.equal((await claim(db)).code,'DENIED');
}));
test('restricted and deleting actors cannot dispatch; suppressed recipients are excluded',()=>run(async db=>{
  for(const [kind,id] of [['member',actor],['family',family],['vault',vault],['memory',memory]]) {
    await db.query('insert into content_safety.restrictions values($1,$2)',[kind,id]);
    assert.equal((await claim(db)).code,'DENIED');await db.exec('delete from content_safety.restrictions');
  }
  await db.query('insert into account_deletion_jobs values($1)',[actor]);
  assert.equal((await claim(db)).code,'DENIED');await db.exec('delete from account_deletion_jobs');
  for(const statement of [
    `insert into account_deletion_jobs values('${recipient}')`,
    `insert into content_safety.restrictions values('member','${recipient}')`,
    `insert into member_blocks values('${actor}','${recipient}')`,
    `insert into member_blocks values('${recipient}','${actor}')`,
    `insert into family_feed_hidden_vaults values('${recipient}','${vault}')`,
  ]) {
    await db.exec(statement);
    assert.deepEqual((await claim(db,{target:await nextMemory(db)})).recipient_ids,[other]);
    await db.exec('delete from account_deletion_jobs; delete from content_safety.restrictions; delete from member_blocks; delete from family_feed_hidden_vaults');
  }
}));
test('20 sender claims per rolling hour; 50 family claims; failed attempts do not consume quota',()=>run(async db=>{
  for(let i=0;i<20;i++)assert.equal((await claim(db,{target:await nextMemory(db)})).allowed,true);
  assert.equal((await claim(db,{target:await nextMemory(db)})).code,'RATE_LIMIT');
  await db.exec("update notification_guard.claims set claimed_at=now()-interval '61 minutes'");
  assert.equal((await claim(db,{target:await nextMemory(db)})).allowed,true);
  await db.exec('delete from notification_guard.claims');
  await db.query(`insert into notification_guard.claims select 'seed-'||g,$1,$2,now() from generate_series(1,49) g`,[family,other]);
  assert.equal((await claim(db,{target:await nextMemory(db)})).allowed,true);
  assert.equal((await claim(db,{target:await nextMemory(db)})).code,'RATE_LIMIT');
  assert.equal((await db.query('select count(*)::int n from notification_guard.claims')).rows[0].n,50);
}));
test('optional screening outbox never double sends; invalid routes fail closed',()=>run(async db=>{
  await db.exec(`create function public.memory_notification_route(uuid,uuid) returns jsonb language sql as
    $$select current_setting('test.route')::jsonb$$`);
  for(const [route,code] of [[{allowed:false},'DENIED'],[{allowed:true,delivery_mode:'outbox'},'OUTBOX']]) {
    await db.query("select set_config('test.route',$1,false)",[JSON.stringify(route)]);
    assert.equal((await claim(db)).code,code);
  }
  await db.query("select set_config('test.route',$1,false)",[JSON.stringify({allowed:true,delivery_mode:'bad'})]);
  await assert.rejects(claim(db),/Invalid notification route/);
  await db.query("select set_config('test.route',$1,false)",[JSON.stringify({allowed:true,delivery_mode:'direct',family_id:family,recipient_ids:[other,outsider]})]);
  assert.deepEqual((await claim(db)).recipient_ids,[other]);
}));
