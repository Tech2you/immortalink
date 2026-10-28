import {test} from 'node:test';
import assert from 'node:assert/strict';
import {moveRequest,retireReportMedia} from './retire_report_media.mjs';
const id='00000000-0000-4000-8000-000000000001';
const job={id,bucket:'vault_photos',source:'a/b/file.png',destination:`a/b/${id}.png`};
test('worker accepts only fixed same-folder memory moves and no path injection',()=>{
  assert.deepEqual(moveRequest(job),{bucketId:job.bucket,sourceKey:job.source,destinationKey:job.destination});
  for(const patch of [{id:'x'},{bucket:'avatars'},{source:'../file.png'},{source:'a//file'},
    {destination:`foreign/b/${id}`},{source:'a\\b/file'},{destination:job.source},{source:'https://evil/a'}])assert.throws(()=>moveRequest({...job,...patch}));
});
test('lost response after committed move is recovered from durable readback',async()=>{
  let moved=false,moves=0;
  const result=await retireReportMedia(async(path)=>{
    if(path.endsWith('next_content_media_retirement'))return moved?null:job;
    if(path.endsWith('/move')){moved=true;moves++;throw new Error('response lost SECRET');}
    return {state:'retired',pending:0};
  },id);
  assert.equal(result.state,'retired');assert.equal(moves,1);
});
test('uncommitted error stays pending and is not retried repeatedly in one request',async()=>{
  let moves=0;
  const request=async(path)=>{
    if(path.endsWith('next_content_media_retirement'))return job;
    if(path.endsWith('/move')){moves++;throw new Error('SECRET');}
    return {state:'pending',pending:1};
  };
  assert.equal((await retireReportMedia(request,id)).state,'pending');assert.equal(moves,1);
  assert.equal((await retireReportMedia(request,id)).state,'pending');assert.equal(moves,2);
});
test('work is bounded and status is queried even when there is no work',async()=>{
  let moves=0;
  const request=async(path)=>{
    if(path.endsWith('next_content_media_retirement'))return {...job,id:`00000000-0000-4000-8000-${String(moves+1).padStart(12,'0')}`};
    if(path.endsWith('/move')){moves++;return {};}
    return {state:'pending',pending:6};
  };
  assert.equal((await retireReportMedia(request,id,{maximum:100})).pending,6);assert.equal(moves,4);
  const calls=[];
  assert.deepEqual(await retireReportMedia(async(path)=>{calls.push(path);return path.endsWith('next_content_media_retirement')?null:{state:'blocked'};},id),{state:'blocked'});
  assert.equal(calls.length,2);
});
