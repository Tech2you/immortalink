import { test } from 'node:test';
import assert from 'node:assert/strict';
import {readNotificationPayload,claimNotification,recipientTokens,sendBounded} from './dispatch_guard.mjs';
const actor='00000000-0000-4000-8000-000000000001';
const member='00000000-0000-4000-8000-000000000002';
const family='00000000-0000-4000-8000-000000000003';
const request=body=>new Request('https://example.test',{method:'POST',body:typeof body==='string'?body:JSON.stringify(body)});
test('payload accepts known events only and discards spoofed actor, audience and HTML/email content',async()=>{
  assert.deepEqual(await readNotificationPayload(request({type:'memory_added',memory_id:family,actor_id:member,
    recipient_ids:[member],body:'<script>alert(1)</script>\r\nBcc:evil@example.test'})),{type:'memory_added',target:family});
  for(const body of ['invalid','x'.repeat(4097),null,{type:'memory_added',memory_id:"'); DROP TABLE memories;--"},{type:'wrong',family_id:family}])
    await assert.rejects(readNotificationPayload(request(body)));
});
test('verified actor reaches RPC; malformed/error responses never send',async()=>{
  let called;
  const admin={rpc:async(...args)=>{called=args;return {data:{allowed:true,family_id:family,recipient_ids:[member,member]}};}};
  assert.deepEqual(await claimNotification(admin,{type:'family_joined',target:family},actor),{code:'CLAIMED',familyId:family,recipientIds:[member]});
  assert.deepEqual(called,['claim_family_notification',{p_type:'family_joined',p_target:family,p_actor:actor}]);
  for(const data of [null,{}, {allowed:true,family_id:family,recipient_ids:[actor]}, {allowed:false,code:'UNKNOWN'}])
    await assert.rejects(claimNotification({rpc:async()=>({data})},{type:'memory_added',target:family},actor));
  await assert.rejects(claimNotification({rpc:async()=>({error:{message:'secret'}})},{type:'memory_added',target:family},actor),/eligibility unavailable/);
});
test('token lookup batches large families, pages all device tokens and fails closed',async()=>{
  const ids=Array.from({length:121},(_,i)=>`member${i}`),calls=[];
  const rows=Array.from({length:401},(_,i)=>({token:String(i).padStart(4,'0')}));
  const admin={from(name){assert.equal(name,'user_push_tokens');let group,after='';const q={
    select(){return q;},in(key,value){group=value;return q;},order(){return q;},limit(){return q;},gt(key,value){after=value;return q;},
    async abortSignal(){calls.push({group,after});return {data:rows.filter(r=>r.token>after).slice(0,200)};}};return q;}};
  assert.equal((await recipientTokens(admin,ids)).length,401);
  assert.equal(calls.length,9);assert(calls.every(c=>c.group.length<=50));
  assert.deepEqual([...new Set(calls.flatMap(c=>c.group))],ids);
  const bad={from(){const q={select:()=>q,in:()=>q,order:()=>q,limit:()=>q,abortSignal:async()=>({error:{message:'secret'}})};return q;}};
  await assert.rejects(recipientTokens(bad,ids),/tokens unavailable/);
});
test('provider sends bound concurrency, count failures and stop at deadline',async()=>{
  let active=0,peak=0;
  const result=await sendBounded(Array.from({length:21},(_,i)=>i),async i=>{
    active++;peak=Math.max(peak,active);await new Promise(r=>setTimeout(r,1));active--;if(i===3)throw new Error('provider token');
  });
  assert.deepEqual(result,{sent:20,failed:1,skipped:0});assert.equal(peak,5);
  assert.deepEqual(await sendBounded([1,2,3],()=>assert.fail('must not send'),{budgetMs:0,now:()=>10}),{sent:0,failed:0,skipped:3});
});
