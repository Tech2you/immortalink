import {test} from 'node:test';import assert from 'node:assert/strict';
import {AiBudgetError,reserveBudget,budgetedJson,reservationCost,settledCost} from './ai_budget.ts';
import {readBoundedJson} from './bounded_json.ts';
const body={model:'gpt-4o-mini',max_tokens:220,messages:[{role:'user',content:'Hello'}]};
function client(options:any={}){const calls:any[]=[];return {calls,async rpc(name:string,args:any){calls.push({name,args});if(options.throw)throw Error('offline');return {data:name==='reserve_ai_budget'?(options.denied?null:'reservation'):null,error:options.error};}};}
test('all paid calls fail closed on budget denial, outage or malformed reservation',async()=>{
 for(const options of [{denied:true},{throw:true},{error:true}]){
  let sent=0;await assert.rejects(budgetedJson(client(options),'chat',body,async()=>{sent++;return Response.json({});}),AiBudgetError);assert.equal(sent,0);
 }
});
test('successful known usage settles; malformed usage and ambiguous failures retain reserve',async()=>{
 for(const response of [()=>Response.json({}),()=>new Response('bad'),()=>new Response('',{status:500}),()=>{throw Error('timeout')}]){
  const db=client();await budgetedJson(db,'chat',body,async()=>response()).catch(()=>{});assert.equal(db.calls.length,1);
 }
 const db=client();await budgetedJson(db,'chat',body,async()=>Response.json({usage:{prompt_tokens:10,completion_tokens:20}}));assert.equal(db.calls[1].args.p_amount,27);
});
test('cancel before dispatch is idempotent and cannot subsequently spend',async()=>{
 const db=client(),r=await reserveBudget(db,'transcription');await r.cancelUnstarted();await r.cancelUnstarted();assert.equal(db.calls.length,2);
 await assert.rejects(r.run(async()=>Response.json({})),AiBudgetError);
 const active=await reserveBudget(db,'chat',body);await active.run(async()=>Response.json({}));await active.cancelUnstarted();assert.equal(db.calls.length,3);
 await assert.rejects(active.run(async()=>Response.json({})),AiBudgetError);
});
test('UTF-8 input, output ceilings and model allowlist bound reservations',()=>{
 assert.ok(reservationCost('chat',{...body,messages:['😀'.repeat(100)]})>reservationCost('chat',body));
 assert.throws(()=>reservationCost('chat',{...body,model:'expensive-model'}),AiBudgetError);
 assert.throws(()=>reservationCost('chat',{...body,max_tokens:261}),AiBudgetError);
 assert.throws(()=>reservationCost('embedding',{model:'text-embedding-3-small',input:['x'.repeat(200001)]}),AiBudgetError);
 assert.equal(settledCost('transcription',{input_tokens:16000,output_tokens:2000}),116000);
 assert.equal(settledCost('chat',{prompt_tokens:-1,completion_tokens:3}),null);
});
test('body size checked even without Content-Length or with a lying header',async()=>{
 for(const headers of [{},{'content-length':'1'}]) await assert.rejects(readBoundedJson(new Request('https://test',{method:'POST',headers,body:'x'.repeat(3000)}),2048),/BODY_TOO_LARGE/);
 assert.deepEqual(await readBoundedJson(new Request('https://test',{method:'POST',body:'{"a":1}'}),100),{a:1});
});
