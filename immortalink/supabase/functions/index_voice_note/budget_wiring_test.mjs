// Exercise the actual transcription orchestration with no network or private audio.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {reserveBudget,AiBudgetError} from '../_shared/ai_budget.ts';
const {runTranscriptionJob,TranscriptionError}=await import('data:text/javascript,'+encodeURIComponent(
 stripTypeScriptTypes(readFileSync(new URL('./transcription_job.ts',import.meta.url),'utf8'),{mode:'transform'})
));
const source=readFileSync(new URL('./index.ts',import.meta.url),'utf8');
const fn=stripTypeScriptTypes(source.slice(source.indexOf('async function verifiedTranscription('),source.indexOf('\nserve(async (req)')));
function fixture(options={}) {
 const calls=[];let paid=0,quota=0;
 const admin={async rpc(name,args){calls.push({name,args});
  if(name==='media_object_matches_scope')return {data:true};
  if(name==='claim_voice_transcription')return {data:options.cached?{claimed:false,status:'succeeded',transcript:'Saved transcript'}:{claimed:true}};
  if(name==='reserve_ai_budget')return {data:options.denied?null:'reservation'};
  if(name==='settle_ai_budget'&&options.refundOutage)throw Error('refund unavailable');
  return {data:null};
 },from(){return {update(value){calls.push({status:value.status});return this;},eq(){return this;},then(resolve){return Promise.resolve({error:null}).then(resolve);}};}};
 const bindings={reserveBudget,AiBudgetError,runTranscriptionJob,TranscriptionError,
  downloadVoiceNoteBytes:async()=>new Uint8Array([0]),validateAudio:async()=>({hash:'fixture-hash',seconds:1}),
  consumeVoiceTranscriptionUsage:async()=>{quota++;return options.quotaDenied?'Family limit reached':null;},
  transcribeWithOpenAI:async({reservation})=>{await reservation.run(async()=>{paid++;if(options.timeout)throw Error('timeout');return Response.json({text:'Fixture transcript'});});return 'Fixture transcript';}
 };
 const run=new Function(...Object.keys(bindings),`${fn};return verifiedTranscription;`)(...Object.values(bindings));
 return {calls,get paid(){return paid;},get quota(){return quota;},run:()=>run({admin,userClient:{},userId:'viewer',apiKey:'fixture',storagePath:'fixture',familyId:'family',memoryId:'memory'})};
}
test('daily cap denial releases unstarted job without family usage or provider call',async()=>{
 const f=fixture({denied:true});await assert.rejects(f.run(),AiBudgetError);assert.equal(f.paid,0);assert.equal(f.quota,0);assert.ok(f.calls.some(x=>x.name==='release_voice_transcription'));
});
test('family quota denial refunds reserve and releases job even during refund outage',async()=>{
 for(const refundOutage of [false,true]){const f=fixture({quotaDenied:true,refundOutage});await assert.rejects(f.run(),/Family limit reached/);assert.equal(f.paid,0);assert.ok(f.calls.some(x=>x.name==='settle_ai_budget'&&x.args.p_amount===0));assert.ok(f.calls.some(x=>x.name==='release_voice_transcription'));}
});
test('ambiguous paid timeout marks failed and retains entire reservation',async()=>{
 const f=fixture({timeout:true});await assert.rejects(f.run(),/timeout/);assert.equal(f.paid,1);assert.ok(f.calls.some(x=>x.status==='failed'));assert.ok(!f.calls.some(x=>['settle_ai_budget','release_voice_transcription'].includes(x.name)));
});
test('cached transcription starts neither payment nor allowance consumption',async()=>{
 const f=fixture({cached:true});assert.equal(await f.run(),'Saved transcript');assert.equal(f.paid,0);assert.equal(f.quota,0);assert.ok(!f.calls.some(x=>x.name==='reserve_ai_budget'));
});
