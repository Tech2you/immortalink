import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { publicationFixture, asUser, approve, dispatched } from './helpers/publication_fixture.mjs';
import { owner, viewer, family, vault, memory, legacyMemory, ids, photoPath, report, act } from './helpers/retirement_fixture.mjs';
import { request, claim, consent, finish } from './helpers/screening_fixture.mjs';

const migration = await readFile(new URL('../migrations/20261024120503_content_screening_client_status.sql',import.meta.url),'utf8');
async function fixture(t,options) {
  const db = await publicationFixture(undefined,options); t.after(()=>db.close());
  await db.exec(migration); return db;
}
async function status(db,{ user=owner,expected=user,target=memory,kind='memory' }={}) {
  return (await asUser(db,user,'select get_content_sharing_status($1,$2,$3) value',[kind,target,expected])).rows[0].value;
}
const audience = async (db,actor=owner,target=memory) => {
  await db.exec("set role service_role; set test.role='service_role'");
  try { return (await db.query('select memory_notification_audience($1,$2) value',[target,actor])).rows[0].value; }
  finally { await db.exec('reset role; reset test.role'); }
};

test('status defaults off without changing queue, permissions or archives',async t=>{
  const db=await fixture(t,{ enforce:false });
  assert.deepEqual(await status(db),{state:'disabled',can_request:false});
  assert.equal((await db.query('select count(*) n from content_safety.screening_jobs')).rows[0].n,0);
  assert.equal((await audience(db)).allowed,true);
});
test('archives are excluded and no permission or sharing intent is inferred',async t=>{
  const db=await fixture(t,{fresh:false});
  assert.deepEqual(await status(db),{state:'archive',can_request:false});
  assert.equal((await audience(db)).allowed,true);
});
test('ready, queued, checking, shared states reflect actual exact-generation publication',async t=>{
  const db=await fixture(t);
  assert.deepEqual(await status(db),{state:'ready',can_request:true});
  assert.deepEqual(await audience(db),{allowed:false});
  assert.equal((await request(db)).code,'QUEUED');
  assert.deepEqual(await status(db),{state:'queued',can_request:false});
  await claim(db);
  assert.deepEqual(await status(db),{state:'checking',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
  const other=await fixture(t); await approve(other);
  assert.deepEqual(await status(other),{state:'shared',can_request:false});
  assert.deepEqual(await audience(other),{allowed:true,family_id:family,recipient_ids:[viewer]});
  await other.query("update memories set body='Edited' where id=$1",[memory]);
  assert.deepEqual(await status(other),{state:'ready',can_request:true});
  assert.deepEqual(await audience(other),{allowed:false});
});
test('permission withdrawal never grants sharing; approved content remains available',async t=>{
  const db=await fixture(t); await consent(db,owner,false); await request(db);
  assert.deepEqual(await status(db),{state:'permission_required',can_request:true});
  assert.deepEqual(await audience(db),{allowed:false});
  await consent(db,owner,true); await approve(db); await consent(db,owner,false);
  assert.deepEqual(await status(db),{state:'shared',can_request:false});
  assert.equal((await audience(db)).allowed,true);
});
test('processing pause does not unpublish cleared content or release pending items',async t=>{
  const db=await fixture(t); await db.exec('update content_safety.screening_controls set enabled=false');
  assert.deepEqual(await status(db),{state:'paused',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
  const other=await fixture(t); await approve(other); await other.exec('update content_safety.screening_controls set enabled=false');
  assert.deepEqual(await status(other),{state:'shared',can_request:false});
  assert.equal((await audience(other)).allowed,true);
});
test('private intent is not represented as shared and does not notify',async t=>{
  const db=await fixture(t); await db.query('update memories set share_to_family_feed=false where id=$1',[memory]);
  assert.deepEqual(await status(db),{state:'not_requested',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
});
test('unsupported audio/video is reported before consent or enqueue',async t=>{
  for(const format of ['voice','video']) await t.test(format,async t=>{
    const db=await fixture(t);
    if(format==='voice') await db.query("insert into memory_voice_notes(memory_id,vault_id,path) values($1,$2,'test.m4a')",[memory,vault]);
    else await db.query(`update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','"video/mp4"') where name=$1`,[photoPath]);
    assert.deepEqual(await status(db),{state:'unsupported',can_request:false});
    assert.equal((await db.query('select count(*) n from content_safety.screening_jobs')).rows[0].n,0);
    assert.deepEqual(await audience(db),{allowed:false});
  });
});
test('held results stay held, and status refresh never resets job budgets or leases',async t=>{
  const db=await fixture(t); await finish(db,await dispatched(db),'review');
  const before=(await db.query('select * from content_safety.screening_jobs')).rows;
  for(let i=0;i<3;i++) assert.deepEqual(await status(db),{state:'held',can_request:false});
  assert.deepEqual((await db.query('select * from content_safety.screening_jobs')).rows,before);
  assert.deepEqual(await audience(db),{allowed:false});
});
test('provider failure stays queued, not shared or falsely complete',async t=>{
  const db=await fixture(t); await finish(db,await dispatched(db),'pending');
  assert.deepEqual(await status(db),{state:'queued',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
});
test('status exposes no foreign, deleted, unknown or archived target details',async t=>{
  const db=await fixture(t);
  for(const options of [{user:viewer},{target:ids[19]},{kind:'vault'}]) {
    assert.deepEqual(await status(db,options),{state:'unavailable',can_request:false});
  }
  await assert.rejects(status(db,{user:owner,expected:viewer}),/Account changed/);
  await assert.rejects(status(db,{user:null}),/Account changed/);
  await db.query('delete from memories where id=$1',[memory]);
  assert.deepEqual(await status(db),{state:'unavailable',can_request:false});
});
test('legacy authors get status; other family members cannot query source status',async t=>{
  const db=await fixture(t);
  assert.deepEqual(await status(db,{kind:'legacy_memory',target:legacyMemory}),{state:'ready',can_request:true});
  assert.deepEqual(await status(db,{kind:'legacy_memory',target:legacyMemory,user:viewer}),{state:'unavailable',can_request:false});
  await approve(db,'legacy_memory',legacyMemory);
  assert.deepEqual(await status(db,{kind:'legacy_memory',target:legacyMemory}),{state:'shared',can_request:false});
});
test('deleted account or departed membership cannot query or notify',async t=>{
  const db=await fixture(t); await approve(db);
  await db.query('delete from family_members where user_id=$1',[owner]);
  assert.deepEqual(await status(db),{state:'unavailable',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
});
test('report hiding overrides completed screening for status and notification',async t=>{
  const db=await fixture(t); await approve(db); await act(db,await report(db),'hide');
  assert.deepEqual(await status(db),{state:'unavailable',can_request:false});
  assert.deepEqual(await audience(db),{allowed:false});
});
test('blocks, hidden feed and recipient suspension exclude only those recipients',async t=>{
  for(const scenario of ['block','reverse','hidden','suspended']) await t.test(scenario,async t=>{
    const db=await fixture(t); await approve(db);
    if(scenario==='block') await db.query('insert into member_blocks(blocker_id,blocked_id) values($1,$2)',[viewer,owner]);
    if(scenario==='reverse') await db.query('insert into member_blocks(blocker_id,blocked_id) values($1,$2)',[owner,viewer]);
    if(scenario==='hidden') await db.query('insert into family_feed_hidden_vaults values($1,$2)',[viewer,vault]);
    if(scenario==='suspended') await db.query("insert into content_safety.restrictions(target_kind,target_id) values('member',$1)",[viewer]);
    assert.deepEqual(await audience(db),{allowed:true,family_id:family,recipient_ids:[]});
  });
});
test('service-only audience cannot be called by app users, including the author',async t=>{
  const db=await fixture(t); await approve(db);
  for(const user of [owner,viewer]) await assert.rejects(
    asUser(db,user,'select memory_notification_audience($1,$2)',[memory,owner]),/permission denied/);
  assert.deepEqual(await audience(db,viewer),{allowed:false});
  await db.exec('set role anon');
  try { await assert.rejects(db.query('select get_content_sharing_status($1,$2,$3)',['memory',memory,owner]),/permission denied/); }
  finally { await db.exec('reset role'); }
});
test('new RPCs pass exact-signature access audit with no new app privileged helper',async t=>{
  const db=await fixture(t);
  const audit=await readFile(new URL('../verification/launch_access_audit.sql',import.meta.url),'utf8');
  const rows=(await db.query(audit)).rows;
  const unexpected=rows.find(r=>r.check_name==='unexpected_client_privileged_functions').findings;
  assert(!unexpected.some(name=>name.includes('sharing')||name.includes('notification')));
  const missing=rows.find(r=>r.check_name==='expected_client_functions_unavailable').findings;
  assert(!missing.some(name=>name.includes('get_content_sharing_status')));
});
