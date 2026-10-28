import { test } from 'node:test';
import assert from 'node:assert/strict';
import { owner, viewer, family, memory, sibling, ids, photoPath, vault } from './helpers/retirement_fixture.mjs';
import { screeningFixture, processingSql, consent, enqueue, claim, prepare, finish } from './helpers/screening_fixture.mjs';

async function fixture(t) {
  const db=await screeningFixture(undefined,true,true);t.after(()=>db.close());return db;
}
const counters=async db=>(await db.query('select scope,subject,window_start,used_bytes,used_jobs,used_images,used_output_bytes from content_safety.screening_processing_budgets order by scope,subject')).rows;
const start=async (db,target=memory)=>{await enqueue(db,'memory',target);return claim(db);};
const expire=async db=>db.exec("update content_safety.screening_jobs set lease_until=now()-interval '1 minute' where state='leased'");

test('processing migration leaves policies, triggers, media and unrelated functions unchanged',async t=>{
  const db=await screeningFixture();t.after(()=>db.close());
  const functions=(await db.query(`select p.oid,pg_get_functiondef(p.oid) body from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','content_safety')
    and p.prokind='f' and p.proname<>'prepare_content_screening' order by p.oid`)).rows;
  const policies=(await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows;
  const triggers=(await db.query('select oid,pg_get_triggerdef(oid) body from pg_trigger order by oid')).rows;
  const objects=(await db.query('select * from storage.objects order by id')).rows;
  await db.exec(processingSql);
  for(const f of functions)assert.equal((await db.query('select pg_get_functiondef($1) body',[f.oid])).rows[0].body,f.body);
  for(const tr of triggers)assert.equal((await db.query('select pg_get_triggerdef($1) body',[tr.oid])).rows[0].body,tr.body);
  assert.deepEqual((await db.query('select * from pg_policies order by schemaname,tablename,policyname')).rows,policies);
  assert.deepEqual((await db.query('select * from storage.objects order by id')).rows,objects);
  assert.doesNotMatch(processingSql,/create\s+(trigger|policy)|net\.http|cron\./i);
});

test('first prepare charges once per lease before content retrieval; rechecks and dispatch do not double charge',async t=>{
  const db=await fixture(t),job=await start(db);
  assert.deepEqual(await counters(db),[]);
  assert.equal((await prepare(db,job)).processing_reserved,true);
  const first=await counters(db);assert.equal(first.length,3);
  assert(first.every(c=>c.used_bytes===10&&c.used_jobs===1&&c.used_images===1));
  assert(first.every(c=>c.used_output_bytes===2097152+2796204+6*Buffer.byteLength('QA\nReported')+1024));
  for(let i=0;i<4;i++)assert.equal((await prepare(db,job)).processing_reserved,true);
  assert.equal((await prepare(db,job,true)).code,'DISPATCH_RESERVED');
  assert.equal((await finish(db,job)).state,'clear');
  assert.deepEqual(await counters(db),first);
});

test('direct dispatch also reserves processing; expired retries spend fresh capacity',async t=>{
  const db=await fixture(t),first=await start(db);
  assert.equal((await prepare(db,first,true)).code,'DISPATCH_RESERVED');
  await expire(db);const second=await claim(db);
  assert.equal((await prepare(db,first)).code,'LEASE_UNAVAILABLE');
  assert.equal((await prepare(db,second)).processing_reserved,true);
  assert((await counters(db)).every(c=>c.used_jobs===2&&c.used_bytes===20&&c.used_images===2));
});

test('each global daily/monthly and per-user hourly input/output byte/job/image ceiling prevents all partial charges',async t=>{
  for(const scope of ['global_day','global_month','user_hour'])for(const resource of ['bytes','jobs','images','output_bytes']){
    await t.test(`${scope}-${resource}`,async t=>{
      const db=await fixture(t);
      const capacity=resource==='bytes'?10:resource==='output_bytes'?2097152+2796204+6*Buffer.byteLength('QA\nReported')+1024:1;
      await db.query(`update content_safety.screening_processing_limits set max_${resource}=$1 where scope=$2`,[capacity,scope]);
      const first=await start(db);await prepare(db,first);
      const before=await counters(db);const second=await start(db,sibling);
      const denied=await prepare(db,second);
      assert.deepEqual(denied,{code:'PROCESSING_BUDGET_LIMIT'});
      assert.deepEqual(await counters(db),before);
      const row=(await db.query('select state,attempts,lease_token,available_at>now() delayed from content_safety.screening_jobs where id=$1',[second.id])).rows[0];
      assert.deepEqual(row,{state:'queued',attempts:0,lease_token:null,delayed:true});
      assert.equal(await claim(db),null);
    });
  }
});

test('source edits and consent withdrawal never refund spent capacity',async t=>{
  const db=await fixture(t),first=await start(db);await prepare(db,first);
  await db.query("update memories set body='New content' where id=$1",[memory]);
  const second=await start(db);await prepare(db,second);
  assert((await counters(db)).every(c=>c.used_jobs===2));
  await consent(db,owner,false);
  assert.equal((await prepare(db,second,true)).code,'SOURCE_CHANGED');
  assert((await counters(db)).every(c=>c.used_jobs===2));
});

test('old counter periods reset in UTC, current monthly budget persists over a daily rollover',async t=>{
  const db=await fixture(t),first=await start(db);await prepare(db,first);
  await db.exec("set time zone 'Pacific/Honolulu';update content_safety.screening_processing_budgets set window_start=window_start-interval '2 days' where scope<>'global_month'");
  const second=await start(db,sibling);await prepare(db,second);
  const rows=await counters(db);
  assert(rows.filter(c=>c.scope!=='global_month').every(c=>c.used_jobs===1));
  assert.equal(rows.find(c=>c.scope==='global_month').used_jobs,2);
  assert.equal(new Date(rows.find(c=>c.scope==='global_day').window_start).getUTCHours(),0);
});

test('missing limits and exhausted provider budget return no files or reservation',async t=>{
  for(const cause of ['missing','provider'])await t.test(cause,async t=>{
    const db=await fixture(t),job=await start(db);
    if(cause==='missing')await db.exec("delete from content_safety.screening_processing_limits where scope='global_month'");
    else await db.exec("insert into content_safety.screening_budgets values('global_day','all',floor(extract(epoch from now())/86400),1000)");
    const result=await prepare(db,job);
    assert.deepEqual(result,{code:cause==='missing'?'PROCESSING_LIMITS_UNAVAILABLE':'BUDGET_LIMIT'});
    assert.deepEqual(await counters(db),[]);
  });
});

test('oversized total batch goes to review before downloading or charging',async t=>{
  const db=await fixture(t);
  // Give only this disposable fixture room for the synthetic 36 MiB batch.
  await db.exec('create or replace function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1073741824::bigint$$');
  for(let i=0;i<2;i++){
    const path=photoPath.replace('photo.png',`extra-${i}.png`);
    await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,path]);
    await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) select bucket_id,$1,owner,owner_id,metadata from storage.objects where name=$2',[path,photoPath]);
  }
  await db.exec("update storage.objects set metadata=jsonb_set(metadata,'{size}','12582912')");
  const result=await prepare(db,await start(db));
  assert.deepEqual(result,{code:'SOURCE_BATCH_TOO_LARGE'});assert.deepEqual(await counters(db),[]);
  assert.equal((await db.query('select state from content_safety.screening_jobs')).rows[0].state,'review');
});

test('text-only costs a processing job but no photo bytes or decodes',async t=>{
  const db=await fixture(t);await db.exec('delete from memory_photos');
  assert.equal((await prepare(db,await start(db))).processing_reserved,true);
  assert((await counters(db)).every(c=>c.used_jobs===1&&c.used_bytes===0&&c.used_images===0));
});

test('per-account limits are independent while all contributors share the global ceiling',async t=>{
  const db=await fixture(t);await consent(db,viewer,true);
  await db.query('insert into vaults(id,owner_id,family_id,name) values($1,$2,$3,$4)',[ids[13],viewer,family,'QA second account']);
  await db.query('insert into memories(id,vault_id,body) values($1,$2,$3)',[ids[14],ids[13],'QA second memory']);
  await db.exec("update content_safety.screening_processing_limits set max_jobs=1 where scope='user_hour'");
  assert.equal((await prepare(db,await start(db))).processing_reserved,true);
  await enqueue(db,'memory',ids[14],viewer);
  assert.equal((await prepare(db,await claim(db))).processing_reserved,true);
  assert((await counters(db)).filter(c=>c.scope==='user_hour').every(c=>c.used_jobs===1));
  assert.equal((await prepare(db,await start(db,sibling))).code,'PROCESSING_BUDGET_LIMIT');
  // Relieve the user ceiling; the independent shared budget still prevents work.
  await db.exec("update content_safety.screening_processing_limits set max_jobs=10 where scope='user_hour';update content_safety.screening_processing_limits set max_jobs=2 where scope='global_day';update content_safety.screening_jobs set available_at=now() where state='queued'");
  assert.equal((await prepare(db,await claim(db))).code,'PROCESSING_BUDGET_LIMIT');
  assert.equal((await counters(db)).find(c=>c.scope==='global_day').used_jobs,2);
});

test('invalid leases, missing consent and disabled screening do not spend capacity',async t=>{
  const db=await fixture(t),job=await start(db);
  assert.equal((await prepare(db,{...job,lease_token:ids[15]})).code,'LEASE_UNAVAILABLE');
  await consent(db,owner,false);assert.equal((await prepare(db,job)).code,'SOURCE_CHANGED');
  await db.exec('update content_safety.screening_controls set enabled=false');
  assert.equal(await claim(db),null);assert.deepEqual(await counters(db),[]);
});

test('clients and service workers cannot directly read or reset private resource budgets',async t=>{
  const db=await fixture(t);
  for(const role of ['anon','authenticated','service_role']){
    await db.exec(`set role ${role}`);
    for(const table of ['screening_processing_limits','screening_processing_budgets']){
      await assert.rejects(db.query(`select * from content_safety.${table}`),/permission denied/);
      await assert.rejects(db.query(`delete from content_safety.${table}`),/permission denied/);
    }
    await db.exec('reset role');
  }
  assert((await db.query("select relrowsecurity rls from pg_class where relname in ('screening_processing_limits','screening_processing_budgets')")).rows.every(r=>r.rls));
});
