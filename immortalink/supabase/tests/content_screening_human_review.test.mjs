import { test } from 'node:test';
import assert from 'node:assert/strict';
import { reviewFixture, reviewSql, statusSql, flagged, queue, preview, decide, inspected, ack } from './helpers/screening_review_fixture.mjs';
import { publicationFixture, asUser, dispatched, approve } from './helpers/publication_fixture.mjs';
import { request, consent, claim, finish } from './helpers/screening_fixture.mjs';
import { memory, legacyMemory, owner, viewer, family, vault, photoPath, sibling, ids, report, act } from './helpers/retirement_fixture.mjs';

async function fixture(t,options){const db=await reviewFixture(undefined,options);t.after(()=>db.close());return db;}
const visible=async db=>(await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length;

test('migration retains existing policies, grants and function identities except the two declared screening helpers',async t=>{
  const db=await publicationFixture();t.after(()=>db.close());await db.exec(statusSql);
  const policies=()=>db.query('select * from pg_policies order by schemaname,tablename,policyname');
  const functions=()=>db.query(`select p.oid,p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) body,p.proacl
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','content_safety','storage') and p.prokind='f' order by p.oid`);
  const beforePolicies=(await policies()).rows,before=(await functions()).rows;
  await db.exec(reviewSql);assert.deepEqual((await policies()).rows,beforePolicies);
  const after=new Map((await functions()).rows.map(row=>[row.oid,row]));
  for(const row of before){
    const current=after.get(row.oid);assert.ok(current,row.signature);
    if(/^(enqueue_content_screening|get_content_sharing_status)\(/.test(row.signature)){
      assert.equal(current.signature,row.signature);assert.deepEqual(current.proacl,row.proacl);
    }else assert.deepEqual(current,row,row.signature);
  }
});
test('migration stays off by default and creates no backfill or user reports',async t=>{
  const db=await fixture(t,{enforce:false,enabled:false});
  assert.deepEqual(await queue(db),[]);
  assert.equal((await db.query('select count(*) n from content_safety.screening_reviews')).rows[0].n,0);
  assert.equal((await db.query('select count(*) n from content_reports')).rows[0].n,0);
  assert.equal((await db.query('select enabled or enforce_publication as enabled from content_safety.screening_controls')).rows[0].enabled,false);
});
test('a valid flagged result creates one private case, no report or publication',async t=>{
  const db=await fixture(t);const id=await flagged(db);const rows=await queue(db);
  assert.equal(rows.length,1);assert.equal(rows[0].id,id);assert.equal(rows[0].reason,'HUMAN_REVIEW_REQUIRED');
  assert.deepEqual(Object.keys(rows[0]).sort(),['created_at','id','reason','status','target_kind']);
  assert.equal(await visible(db),0);assert.equal((await db.query('select count(*) n from content_reports')).rows[0].n,0);
  for(let i=0;i<3;i++)assert.equal((await request(db)).state,'review');
  assert.equal((await queue(db)).length,1);assert.equal(await claim(db),null);
});
test('provider clear creates no held case; failed result retries do not publish',async t=>{
  const db=await fixture(t);await approve(db);assert.deepEqual(await queue(db),[]);assert.equal(await visible(db),1);
  const other=await fixture(t);const job=await dispatched(other);await other.query('update content_safety.screening_jobs set attempts=3 where id=$1',[job.id]);
  assert.equal((await finish(other,job,'pending')).code,'RETRY_LIMIT');
  assert.equal((await queue(other))[0].reason,'RETRY_LIMIT');assert.equal(await visible(other),0);
});
test('claim retry exhaustion creates a case without another provider reservation',async t=>{
  const db=await fixture(t);await request(db);await db.exec('update content_safety.screening_jobs set attempts=3');
  assert.equal(await claim(db),null);assert.equal((await queue(db))[0].reason,'RETRY_LIMIT');
  assert.equal((await db.query('select count(*) n from content_safety.screening_budgets')).rows[0].n,0);
});
test('text and every direct image must be previewed recently by the deciding reviewer',async t=>{
  const db=await fixture(t);const id=await flagged(db);
  const raw=(await db.query('select content_safety.screening_review_snapshot($1) value',[id])).rows[0].value;
  await assert.rejects(decide(db,id,raw.revision),/SAFETY_PREVIEW_REQUIRED/);
  const data=await preview(db,id);assert.equal(data.media.length,1);
  await assert.rejects(decide(db,id,data.revision),/SAFETY_MEDIA_PREVIEW_REQUIRED/);
  await inspected(db,id);await assert.rejects(decide(db,id,data.revision,'approve','Another reviewer'),/SAFETY_PREVIEW_REQUIRED/);
  assert.equal((await decide(db,id,data.revision)).status,'approved');assert.equal(await visible(db),1);
  await assert.rejects(decide(db,id,data.revision),/SAFETY_CASE_CHANGED/);
  assert.equal((await queue(db,'approved')).length,1);assert.deepEqual(await queue(db),[]);
  assert.equal((await db.query("select count(*) n from content_safety.screening_review_events where action='approve'")).rows[0].n,1);
});
test('previewing one of several images cannot approve the unviewed remainder',async t=>{
  const db=await fixture(t),path=photoPath.replace('photo.png','second.png');
  await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) select bucket_id,$1,owner,owner_id,metadata from storage.objects where name=$2',[path,photoPath]);
  await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,path]);
  const id=await flagged(db),data=await preview(db,id);assert.equal(data.media.length,2);
  await preview(db,id,'QA',data.media[0].id,data.revision);await ack(db,id,data.media[0].id,data.revision);
  await assert.rejects(decide(db,id,data.revision),/SAFETY_MEDIA_PREVIEW_REQUIRED/);assert.equal(await visible(db),0);
  await preview(db,id,'QA',data.media[1].id,data.revision);await ack(db,id,data.media[1].id,data.revision);
  assert.equal((await decide(db,id,data.revision)).status,'approved');
});
test('personal and legacy approvals release only their exact target',async t=>{
  for(const kind of ['memory','legacy_memory'])await t.test(kind,async t=>{
    const db=await fixture(t);const id=await flagged(db,kind,kind==='memory'?memory:legacyMemory);const data=await inspected(db,id);
    assert.equal(data.report.kind,kind);assert.equal(data.report.accountActionAvailable,false);
    await decide(db,id,data.revision);
    assert.equal((await asUser(db,viewer,`select id from ${kind==='memory'?'memories':'legacy_memories'} where id=$1`,[kind==='memory'?memory:legacyMemory])).rows.length,1);
    assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[sibling])).rows.length,0);
  });
});
test('held queue is revisitable and holding never deletes or publishes',async t=>{
  const db=await fixture(t);const id=await flagged(db);let data=await preview(db,id);
  await decide(db,id,data.revision,'hold');assert.deepEqual(await queue(db),[]);assert.equal((await queue(db,'held'))[0].id,id);
  assert.equal(await visible(db),0);assert.equal((await db.query('select count(*) n from memories where id=$1',[memory])).rows[0].n,1);
  data=await inspected(db,id);await decide(db,id,data.revision);assert.equal(await visible(db),1);
});
test('withdraw/reaccept cannot reroll a flag or grant provider permission via human approval',async t=>{
  const db=await fixture(t);const id=await flagged(db);const before=(await db.query('select * from content_safety.screening_jobs')).rows;
  await consent(db,owner,false);await consent(db,owner,true);assert.equal((await request(db)).state,'review');
  assert.deepEqual((await db.query('select * from content_safety.screening_jobs')).rows,before);
  assert.deepEqual((await asUser(db,owner,'select get_content_sharing_status($1,$2,$3) value',['memory',memory,owner])).rows[0].value,{state:'held',can_request:false});
  await consent(db,owner,false);const permissions=(await db.query('select * from content_safety.screening_permissions')).rows;
  const data=await inspected(db,id);await decide(db,id,data.revision);
  assert.deepEqual((await db.query('select * from content_safety.screening_permissions')).rows,permissions);
  assert.equal(await visible(db),1);assert.equal(await claim(db),null);
  assert.deepEqual((await asUser(db,owner,'select get_content_sharing_status($1,$2,$3) value',['memory',memory,owner])).rows[0].value,{state:'shared',can_request:false});
});
test('content editing, reverting, media changes and deletion invalidate the old case',async t=>{
  for(const mode of ['edit','revert','bytes','attachment','delete','family'])await t.test(mode,async t=>{
    const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
    if(['edit','revert'].includes(mode))await db.query("update memories set body='New text' where id=$1",[memory]);
    if(mode==='revert')await db.query("update memories set body='Reported' where id=$1",[memory]);
    if(mode==='bytes')await db.query(`update storage.objects set metadata=jsonb_set(metadata,'{eTag}','"replacement"') where name=$1`,[photoPath]);
    if(mode==='attachment')await db.query('delete from memory_photos where memory_id=$1',[memory]);
    if(mode==='delete')await db.query('delete from memories where id=$1',[memory]);
    if(mode==='family')await db.query('update vaults set family_id=$1 where id=$2',[ids[18],vault]);
    await assert.rejects(decide(db,id,data.revision),/SAFETY_CASE_CHANGED/);
    const after=await preview(db,id);assert.equal(after.available,false);assert.deepEqual(after.fields,{});assert.deepEqual(after.media,[]);
    assert.equal((await queue(db,'obsolete')).length,1);assert.equal(await visible(db),0);
  });
});
test('existing report restrictions and sexual-content escalation cannot be bypassed',async t=>{
  for(const mode of ['memory','vault','family','member','sexual'])await t.test(mode,async t=>{
    const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
    if(mode==='sexual')await db.query("insert into content_reports(reporter_id,family_id,target_kind,target_id,reason) values($1,$2,'memory',$3,'sexual_content')",[viewer,family,memory]);
    else await db.query('insert into content_safety.restrictions(target_kind,target_id) values($1,$2)',[mode,mode==='memory'?memory:mode==='vault'?vault:mode==='family'?family:owner]);
    await assert.rejects(decide(db,id,data.revision),/SAFETY_CASE_CHANGED/);
    assert.equal((await preview(db,id)).available,false);
  });
});
test('membership loss prevents approval of the old source',async t=>{
  const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
  await db.query('delete from family_members where user_id=$1',[owner]);
  assert.equal((await preview(db,id)).available,false);await assert.rejects(decide(db,id,data.revision),/SAFETY_CASE_CHANGED/);
});
test('account-deletion initiation prevents approval without deleting retained content',async t=>{
  const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
  await db.query('select claim_account_deletion($1,$2)',[owner,ids[15]]);
  assert.equal((await preview(db,id)).available,false);await assert.rejects(decide(db,id,data.revision),/SAFETY_CASE_CHANGED/);
  assert.equal((await db.query('select count(*) n from legacy_memories where id=$1',[legacyMemory])).rows[0].n,1);
});
test('preview expiry, tampered media, invalid actions and empty notes are rejected',async t=>{
  const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
  await assert.rejects(preview(db,id,'QA',ids[19],data.revision),/SAFETY_MEDIA_UNAVAILABLE/);
  for(const action of ['restore','dismiss','suspend','reinstate',null])await assert.rejects(decide(db,id,data.revision,action),/SAFETY_REVIEW_REQUIRED/);
  await assert.rejects(decide(db,id,data.revision,'approve','QA',''),/SAFETY_REVIEW_REQUIRED/);
  await db.exec("update content_safety.screening_review_events set created_at=now()-interval '31 minutes'");
  await assert.rejects(decide(db,id,data.revision),/SAFETY_PREVIEW_REQUIRED/);assert.equal(await visible(db),0);
});
test('only unavailable cases may be closed without publishing',async t=>{
  const db=await fixture(t);const id=await flagged(db);let data=await preview(db,id);
  await assert.rejects(decide(db,id,data.revision,'obsolete'),/SAFETY_CASE_CHANGED/);
  await db.query('delete from family_members where user_id=$1',[owner]);data=await preview(db,id);
  await decide(db,id,data.revision,'obsolete');assert.equal(await visible(db),0);
});
test('disabling enforcement prevents preview and approval; worker pause alone permits deliberate human review',async t=>{
  const db=await fixture(t);const id=await flagged(db);const data=await inspected(db,id);
  await db.exec('update content_safety.screening_controls set enabled=false');assert.equal((await preview(db,id)).available,true);
  await db.exec('update content_safety.screening_controls set enforce_publication=false');
  assert.equal((await preview(db,id)).available,false);assert.deepEqual(await queue(db),[]);
  await assert.rejects(decide(db,id,data.revision),/SCREENING_REVIEW_DISABLED/);
});
test('new service endpoints and private tables are denied to both app roles',async t=>{
  const db=await fixture(t);
  for(const role of ['anon','authenticated']) {
    await db.exec(`set role ${role}`);
    for(const sql of ["select screening_review_queue()",`select preview_screening_review('${ids[19]}','QA')`,
      `select decide_screening_review('${ids[19]}','approve','QA','QA','bad')`,
      `select ack_screening_review_media('${ids[19]}','QA','${ids[18]}','bad')`,
      `select content_safety.screening_review_snapshot('${ids[19]}')`,
      'select * from content_safety.screening_reviews','select * from content_safety.screening_review_events'])await assert.rejects(db.exec(sql),/permission denied/);
    await db.exec('reset role');
  }
  await db.exec('set role service_role');
  for(const sql of [`select content_safety.screening_review_snapshot('${ids[19]}')`,
    'select * from content_safety.screening_reviews','select * from content_safety.screening_review_events'])await assert.rejects(db.exec(sql),/permission denied/);
  await db.exec('reset role');
});
test('requesting media without a verified retrieval cannot satisfy the approval check',async t=>{
  const db=await fixture(t);const id=await flagged(db);const data=await preview(db,id);
  await assert.rejects(ack(db,id,data.media[0].id,data.revision),/SAFETY_PREVIEW_REQUIRED/);
  await preview(db,id,'QA',data.media[0].id,data.revision);
  await assert.rejects(decide(db,id,data.revision),/SAFETY_MEDIA_PREVIEW_REQUIRED/);
  await ack(db,id,data.media[0].id,data.revision);await decide(db,id,data.revision);
});
test('existing user report preview/hide/retirement stays independent',async t=>{
  const db=await fixture(t);const id=await flagged(db);const rid=await report(db);await act(db,rid,'hide');
  assert.equal((await preview(db,id)).available,false);
  assert.equal((await db.query('select status from content_reports where id=$1',[rid])).rows[0].status,'resolved');
  assert.equal((await db.query('select state from content_safety.screening_reviews where id=$1',[id])).rows[0].state,'open');
});
