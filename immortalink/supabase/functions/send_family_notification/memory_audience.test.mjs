import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { memoryAudience } from './memory_audience.mjs';
const actor='00000000-0000-4000-8000-000000000001';
const recipient='00000000-0000-4000-8000-000000000002';
const family='00000000-0000-4000-8000-000000000003';
const memory='00000000-0000-4000-8000-000000000004';
test('notification eligibility uses verified actor, not client-supplied owner or audience',async()=>{
  const calls=[];
  const admin={rpc:async(name,params)=>{calls.push([name,params]);return {data:{allowed:true,delivery_mode:'direct',family_id:family,recipient_ids:[recipient,recipient]}};}};
  assert.deepEqual(await memoryAudience(admin,memory,actor),{familyId:family,recipientIds:[recipient],mode:'direct'});
  assert.deepEqual(calls,[['memory_notification_route',{p_memory:memory,p_actor:actor}]]);
});
test('denied, malformed or missing eligibility never falls back to author read access',async()=>{
  for(const data of [null,{},true,{allowed:false},{allowed:'true'}])
    assert.equal(await memoryAudience({rpc:async()=>({data})},memory,actor),null);
  for(const data of [{allowed:true},{allowed:true,family_id:family,recipient_ids:[actor]},
    {allowed:true,family_id:family,recipient_ids:['bad']},{allowed:true,family_id:'bad',recipient_ids:[]}])
    await assert.rejects(memoryAudience({rpc:async()=>({data})},memory,actor),/Invalid notification audience/);
  await assert.rejects(memoryAudience({rpc:async()=>({error:{message:'missing RPC'}})},memory,actor),/eligibility unavailable/);
});
test('handler claims server-authorized audience before token lookup and Firebase; no content enters push',async()=>{
  const source=await readFile(new URL('./index.ts',import.meta.url),'utf8');
  assert(source.indexOf('await claimNotification(')<source.indexOf('await recipientTokens('));
  assert(source.indexOf('await claimNotification(')<source.indexOf('const firebase = await getFirebaseConfig()'));
  assert(source.includes('const recipientIds = audience.recipientIds'));
  assert(source.indexOf('if (audience.code !== "CLAIMED") return')<source.indexOf('await recipientTokens('));
  assert(!source.includes('.from("memories")'));
  assert(!source.includes('Open Ever Roots'));
});
test('outbox routing is explicit; missing or invalid routing fails closed',async()=>{
  const data={allowed:true,delivery_mode:'outbox',family_id:family,recipient_ids:[recipient]};
  assert.equal((await memoryAudience({rpc:async()=>({data})},memory,actor)).mode,'outbox');
  for(const mode of [undefined,null,'DIRECT','unknown'])await assert.rejects(
    memoryAudience({rpc:async()=>({data:{...data,delivery_mode:mode}})},memory,actor),/Invalid/);
});
