import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {deliveryFixture,deliverySql,issue,claimDelivery,authorize,finishDelivery,health,leased} from './helpers/delivery_fixture.mjs';
import {reviewFixture,flagged,inspected,decide} from './helpers/screening_review_fixture.mjs';
import {approve,asUser} from './helpers/publication_fixture.mjs';
import {memory,viewer,owner,family,vault,ids,report,act,legacyMemory,photoPath,finish as retire} from './helpers/retirement_fixture.mjs';
async function fixture(t,on=true){const db=await deliveryFixture(undefined,on);t.after(()=>db.close());return db;}
const deliveries=async db=>(await db.query('select * from content_safety.screening_deliveries order by channel,id')).rows;
const expire=async db=>db.exec("update content_safety.screening_deliveries set lease_until=now()-interval '1 second',next_attempt_at=now()-interval '1 second'");

test('delivery migration defaults off with no backfill, provider work or existing user-report changes',async t=>{
  const db=await fixture(t,false);await flagged(db);assert.deepEqual(await deliveries(db),[]);
  assert.equal(await issue(db),null);assert.equal((await health(db)).enabled,false);
  assert.equal((await db.query('select count(*) n from content_reports')).rows[0].n,0);
});
test('flag produces one privacy-minimal alert; exact approval produces one device notice',async t=>{
  const db=await fixture(t);const id=await flagged(db);assert.equal((await deliveries(db)).length,1);
  const token=await issue(db);assert.match(token,/^[a-f0-9]{64}$/);
  const job=await claimDelivery(db,token);await assert.rejects(claimDelivery(db,token),/UNAUTHORIZED/);
  assert.deepEqual(Object.keys(job).sort(),['channel','id','lease']);
  const grant=await authorize(db,job);assert.equal(grant.case_id,id);assert.equal(await authorize(db,job),null);
  assert.equal(JSON.stringify(grant).includes('Reported'),false);
  assert.equal(await finishDelivery(db,job),true);assert.equal(await finishDelivery(db,job),false);
  const data=await inspected(db,id);await decide(db,id,data.revision);
  const push=await leased(db,'push'),send=await authorize(db,push);
  assert.equal(send.token,'fixture-device-token');assert.equal(send.family_id,family);
  assert.deepEqual(Object.keys(send).sort(),['channel','event_id','family_id','id','send_before','token']);
  assert.equal(await finishDelivery(db,push),true);assert.equal((await health(db)).accepted,2);
  assert.equal(await issue(db,'push'),null);
});
test('automatic clear and human approval support personal and legacy sources without notifying authors',async t=>{
  for(const kind of ['memory','legacy_memory'])await t.test(kind,async t=>{
    const db=await fixture(t);if(kind==='memory')await approve(db);
    else{const id=await flagged(db,kind,legacyMemory);const data=await inspected(db,id);await decide(db,id,data.revision);}
    const rows=(await deliveries(db)).filter(r=>r.channel==='push');assert.equal(rows.length,1);assert.equal(rows[0].recipient_id,viewer);
    assert.equal((await authorize(db,await leased(db,'push'))).family_id,family);
  });
});
test('edits, retries, repeated clearance and report Hide/retirement/Restore preserve reads without duplicate notices',async t=>{
  const db=await fixture(t);await approve(db);const initial=await deliveries(db);
  await db.exec('update content_safety.screening_origins set cleared_generation=cleared_generation');
  const rid=await report(db);await act(db,rid,'hide');
  assert.equal(await authorize(db,await leased(db,'push')),null);
  await retire(db,rid);await act(db,rid,'restore');
  assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length,1);
  const path=(await db.query('select path from memory_photos where memory_id=$1',[memory])).rows[0].path;
  assert.notEqual(path,photoPath);
  assert.equal((await asUser(db,viewer,'select id from storage.objects where name=$1',[path])).rows.length,1);
  assert.equal((await asUser(db,viewer,'select id from storage.objects where name=$1',[photoPath])).rows.length,0);
  await db.query("update memories set body='Changed' where id=$1",[memory]);
  assert.equal((await db.query('select count(*) n from content_safety.screening_notices')).rows[0].n,1);
  assert.equal((await deliveries(db)).length,initial.length);
});
test('subsequent edit approvals do not resend a first-publication notice or retarget a stale one',async t=>{
  const db=await fixture(t);await approve(db);
  await db.query("update memories set body='Changed' where id=$1",[memory]);await approve(db);
  assert.equal((await deliveries(db)).length,1);
  assert.equal(await authorize(db,await leased(db,'push')),null);
});
test('delivery migration preserves every pre-existing function, ACL, RLS policy and table permission',async t=>{
  const db=await reviewFixture();t.after(()=>db.close());
  await db.exec(await readFile(new URL('../migrations/20260826185243_add_user_push_tokens.sql',import.meta.url),'utf8'));
  const snapshot=async()=>({
    functions:(await db.query(`select p.oid,p.proacl::text acl,pg_get_functiondef(p.oid) definition from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','content_safety','storage') and p.prokind='f' order by p.oid`)).rows,
    tables:(await db.query(`select c.oid,c.relacl::text acl,c.relrowsecurity,c.relforcerowsecurity from pg_class c
      join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','content_safety','storage','auth') and c.relkind='r' order by c.oid`)).rows,
    policies:(await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows,
  });
  const before=await snapshot();await db.exec(deliverySql);const after=await snapshot();
  for(const key of ['functions','tables'])assert.deepEqual(after[key].filter(r=>before[key].some(old=>old.oid===r.oid)),before[key]);
  assert.deepEqual(after.policies,before.policies);
});
test('bounded attempts, abandoned leases and explicit push uncertainty require operator attention',async t=>{
  const db=await fixture(t);await flagged(db);
  for(let i=0;i<3;i++){const job=await leased(db);await authorize(db,job);await finishDelivery(db,job,'UNKNOWN');await expire(db);}
  assert.equal(await issue(db),null);assert.equal((await deliveries(db))[0].state,'failed');assert.equal((await health(db)).email_attempts,3);
  const id=await flagged(db,'legacy_memory',legacyMemory);
  for(let i=0;i<8;i++){assert.ok(await issue(db));await expire(db);}
  assert.equal(await issue(db),null);assert.equal((await health(db)).email_attempts,3);
  const data=await inspected(db,id);await decide(db,id,data.revision);const push=await leased(db,'push');await authorize(db,push);
  await finishDelivery(db,push,'UNKNOWN');assert.equal(await issue(db,'push'),null);
  assert.equal((await deliveries(db)).find(d=>d.channel==='push').state,'uncertain');
});
test('dispatch rechecks blocks, membership, hidden feeds, deletion, token ownership, source edits and report hide',async t=>{
  for(const mode of ['block','left','hidden','deleting','token','edit','hide','scope','delete'])await t.test(mode,async t=>{
    const db=await fixture(t);await approve(db);const job=await leased(db,'push');
    if(mode==='block')await db.query('insert into member_blocks(blocker_id,blocked_id) values($1,$2)',[viewer,owner]);
    if(mode==='left')await db.query('delete from family_members where user_id=$1',[viewer]);
    if(mode==='hidden')await db.query('insert into family_feed_hidden_vaults values($1,$2)',[viewer,vault]);
    if(mode==='deleting')await db.query('select claim_account_deletion($1,$2)',[owner,ids[15]]);
    if(mode==='token')await db.query('update user_push_tokens set user_id=$1',[owner]);
    if(mode==='edit')await db.query("update memories set body='New text' where id=$1",[memory]);
    if(mode==='hide')await act(db,await report(db),'hide');
    if(mode==='scope')await db.query('update vaults set family_id=$1 where id=$2',[ids[17],vault]);
    if(mode==='delete')await db.query('delete from memories where id=$1',[memory]);
    assert.equal(await authorize(db,job),null);assert.equal((await health(db)).push_attempts,0);
  });
});
test('handled, obsolete or restricted automatic cases do not email after their state changes',async t=>{
  for(const mode of ['held','edit','restriction'])await t.test(mode,async t=>{
    const db=await fixture(t),id=await flagged(db),job=await leased(db);
    if(mode==='held'){const data=await inspected(db,id);await decide(db,id,data.revision,'hold');}
    if(mode==='edit')await db.query("update memories set body='New text' where id=$1",[memory]);
    if(mode==='restriction')await act(db,await report(db),'hide');
    assert.equal(await authorize(db,job),null);assert.equal((await health(db)).email_attempts,0);
  });
});
test('email crash recovery keeps stable case ID; push ambiguity is never automatically resent',async t=>{
  const db=await fixture(t);const id=await flagged(db),job=await leased(db);await authorize(db,job);await expire(db);
  const recovered=await leased(db);assert.notEqual(recovered.lease,job.lease);
  assert.equal((await authorize(db,recovered)).case_id,id);assert.equal(await finishDelivery(db,job),false);
  await finishDelivery(db,recovered);const data=await inspected(db,id);await decide(db,id,data.revision);
  const push=await leased(db,'push');await authorize(db,push);await expire(db);
  assert.equal(await issue(db,'push'),null);assert.equal((await deliveries(db)).find(d=>d.channel==='push').state,'uncertain');
  assert.equal((await health(db)).attention,1);
});
test('known retries respect attempts, provider backoff and the email idempotency window',async t=>{
  const db=await fixture(t);await flagged(db);let job=await leased(db);await authorize(db,job);
  await finishDelivery(db,job,'RETRY',3600);assert.equal(await issue(db),null);await expire(db);
  job=await leased(db);await authorize(db,job);await finishDelivery(db,job,'UNKNOWN');await expire(db);
  await db.exec("update content_safety.screening_deliveries set first_attempt_at=now()-interval '24 hours'");
  assert.equal(await issue(db),null);assert.equal((await deliveries(db))[0].state,'failed');
});
test('daily caps, queue bounds and disabled channels do not grant dispatch or block a valid save',async t=>{
  const db=await fixture(t);await db.exec('update content_safety.screening_delivery_config set max_pending=1,email_daily_limit=1');
  const id=await flagged(db);const job=await leased(db);await authorize(db,job);await finishDelivery(db,job,'RETRY');await expire(db);
  assert.equal(await issue(db),null);assert.equal((await health(db)).email_attempts,1);
  await db.exec("update content_safety.screening_delivery_config set budget_day=current_date-1");
  const next=await leased(db);assert.ok(await authorize(db,next));
  const data=await inspected(db,id);await decide(db,id,data.revision);
  assert.equal((await health(db)).omitted,1);assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length,1);
  await db.exec('update content_safety.screening_delivery_config set email_enabled=false');
  assert.equal(await issue(db),null);
});
test('expired invocations, invalid leases and app roles cannot dispatch or inspect private delivery metadata',async t=>{
  const db=await fixture(t);await flagged(db);const token=await issue(db);
  await db.exec("update content_safety.screening_deliveries set invocation_expires=now()-interval '1 second'");
  await assert.rejects(claimDelivery(db,token),/UNAUTHORIZED/);
  for(const role of ['anon','authenticated']){
    await db.exec(`set role ${role}`);
    for(const sql of ["select issue_screening_delivery('email')","select claim_screening_delivery('bad')",'select screening_delivery_health()',"select dispatch_screening_delivery('email')",
      `select authorize_screening_delivery('${ids[18]}','${ids[19]}')`,`select finish_screening_delivery('${ids[18]}','${ids[19]}','ACCEPTED')`,
      'select * from content_safety.screening_deliveries','select * from content_safety.screening_notices'])await assert.rejects(db.exec(sql),/permission denied/);
    await db.exec('reset role');
  }
});
test('old immediate sender is routed away from enrolled sources without granting access to pending items',async t=>{
  const db=await fixture(t);
  let route=(await db.query('select memory_notification_route($1,$2) data',[memory,owner])).rows[0].data;
  assert.equal(route.allowed,false);assert.equal(route.delivery_mode,'outbox');
  await approve(db);route=(await db.query('select memory_notification_route($1,$2) data',[memory,owner])).rows[0].data;
  assert.equal(route.allowed,true);assert.equal(route.delivery_mode,'outbox');
  await db.exec('update content_safety.screening_controls set enforce_publication=false');
  assert.equal((await db.query('select memory_notification_route($1,$2) data',[memory,owner])).rows[0].data.delivery_mode,'direct');
});
