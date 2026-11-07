import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createScreeningHandler } from './worker_transport.mjs';
const token='a'.repeat(64);
const request=(value=token)=>new Request('https://example.invalid',{method:'POST',headers:{'x-screening-run-token':value}});

test('disabled, malformed and replayed requests cannot start work',async()=>{
  let claims=0,runs=0,available=true;
  const backend={rpc:async name=>{if(name==='claim_screening_run'){claims++;const result=available;available=false;return result;}return true;}};
  const options={enabled:true,backend,apiKey:'fake-test-only',prepareImage:async()=>{},run:async()=>{runs++;}};
  assert.equal((await createScreeningHandler({...options,enabled:false})(request())).status,503);
  const handler=createScreeningHandler(options);
  assert.equal((await handler(request('invalid'))).status,401);assert.equal(claims,0);
  assert.equal((await handler(request())).status,202);assert.equal(runs,1);
  assert.equal((await handler(request())).status,401);assert.equal(runs,1);
});

test('background work is registered and only returns fixed diagnostics',async()=>{
  let finish=0,task,complete;
  const gate=new Promise(resolve=>{complete=resolve;});
  const handler=createScreeningHandler({enabled:true,apiKey:'fake-test-only',prepareImage:async()=>{},
    backend:{rpc:async name=>{if(name==='finish_screening_run')finish++;return true;}},
    run:async()=>{await gate;throw Error('PRIVATE CONTENT');},waitUntil:value=>{task=value;}});
  const response=await handler(request());assert.equal(response.status,202);
  assert.equal(finish,0);complete();await task;assert.equal(finish,1);
  assert.deepEqual(await response.json(),{code:'SCREENING_ACCEPTED'});
});
