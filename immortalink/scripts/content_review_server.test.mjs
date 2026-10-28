import { test } from 'node:test';
import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { startReviewServer,storagePath,mediaType,publicCase,makeBackend,readBounded } from './content_review_server.mjs';
const id='00000000-0000-4000-8000-000000000001';
const mediaId='00000000-0000-4000-8000-000000000002';
const version='a'.repeat(32);
const snapshot={ report:{id,kind:'legacy_memory',status:'open',reason:'privacy',details:'<script>alert(1)</script>'},available:true,fields:{Memory:'Example'},scopeNote:'Current memory',revision:version,
  media:[{id:mediaId,kind:'image',bucket:'vault_photos',path:'private/photo.png',stamp:'now'}] };
const png=Buffer.from([137,80,78,71,13,10,26,10]);
async function fixture(){
  const calls=[];let time=0;
  const backend={request:async(path,body)=>{calls.push({path,body});
    if(path.includes('preview_content_report'))return body.p_media_id?snapshot.media[0]:snapshot;
    if(path.includes('next_content_media_retirement'))return null;
    if(path.includes('content_report_media_status'))return {state:'retired',hidden:true,pending:0,completed:1};
    if(path.includes('review_content_report_checked'))return {id,action:body.p_action,status:'resolved'};
    return [];},download:async()=>png};
  const app=await startReviewServer({backend,reviewer:'Ross',now:()=>time});
  const origin=new URL(app.url).origin;
  const post=(path,body={},headers={})=>fetch(`${origin}${path}`,{method:'POST',headers:{origin,'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
  const response=await post('/session',{key:new URL(app.url).hash.slice(1)});
  const cookie=response.headers.get('set-cookie').split(';')[0];const {csrf}=await response.json();
  return {...app,origin,calls,backend,post,headers:{Cookie:cookie,'X-Review-CSRF':csrf},advance:()=>{time=600000;},expire:()=>{time=1800001;}};
}
test('reload resumes only the existing cookie-bound session without extending expiry',async()=>{
  const app=await fixture();try{
    assert.equal((await app.post('/session')).status,401);
    assert.equal((await app.post('/session',{}, {Cookie:'unrelated=value'})).status,401);
    app.advance();
    const resumed=await app.post('/session',{}, {Cookie:app.headers.Cookie});
    assert.equal(resumed.status,200);
    assert.equal(resumed.headers.get('set-cookie'),null);
    const body=await resumed.json();
    assert.equal(body.csrf,app.headers['X-Review-CSRF']);
    assert.equal(body.expiresInMs,1200000);
    assert.equal((await app.post('/session',{}, {...app.headers,origin:'https://evil.example'})).status,403);
    assert.equal((await app.post('/session',{key:'wrong'},app.headers)).status,403);
    app.expire();
    assert.equal((await app.post('/session',{},app.headers)).status,401);
  }finally{await app.close();}
});
test('loopback console requires one-time entry, session cookie, CSRF and same origin',async()=>{
  const app=await fixture();try{
    assert.equal((await app.post('/session',{key:new URL(app.url).hash.slice(1)})).status,403);
    assert.equal((await app.post('/api/queue')).status,401);
    assert.equal((await app.post('/api/queue',{},app.headers)).status,200);
    assert.equal((await app.post('/api/queue',{}, {...app.headers,origin:'https://evil.example'})).status,403);
    // Node fetch replaces Host; use HTTP directly to exercise DNS-rebinding defense.
    const hostileHost=await new Promise((resolve,reject)=>{
      const req=httpRequest(`${app.origin}/`,{headers:{Host:'evil.example'}},(response)=>{response.resume();resolve(response.statusCode);});
      req.on('error',reject);req.end();
    });
    assert.equal(hostileHost,403);
    assert.equal((await app.post('/api/queue',{}, {...app.headers,'sec-fetch-site':'cross-site'})).status,403);
    assert.equal((await app.post('/api/queue',{}, {'Cookie':app.headers.Cookie})).status,401);
    app.expire();assert.equal((await app.post('/api/queue',{},app.headers)).status,401);
  }finally{await app.close();}
});
test('case responses redact storage references and use no-store/security headers',async()=>{
  const app=await fixture();try{
    const response=await app.post('/api/case',{id},app.headers);const data=await response.json();
    assert.equal(response.headers.get('cache-control'),'no-store, max-age=0');
    assert.match(response.headers.get('content-security-policy'),/frame-ancestors 'none'/);
    assert.equal(JSON.stringify(data).includes('private/photo.png'),false);assert.equal(JSON.stringify(data).includes('vault_photos'),false);
    assert.deepEqual(data.media,[{id:mediaId,kind:'image'}]);
    assert.equal(app.calls[0].body.p_reviewer,'Ross');
  }finally{await app.close();}
});
test('media is reauthorized before and after retrieval and never embeds a signed URL',async()=>{
  const app=await fixture();try{
    const response=await app.post('/api/media',{id,mediaId,revision:version},app.headers);
    assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/png');
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),png);assert.equal(app.calls.length,2);
    assert.equal(app.calls[0].body.p_media_id,mediaId);
    app.backend.download=async()=>{throw new Error('SECRET private provider response');};
    const failed=await app.post('/api/media',{id,mediaId,revision:version},app.headers);
    assert.equal((await failed.text()).includes('SECRET'),false);
  }finally{await app.close();}
});
test('decisions require exact reference and notes and use the checked RPC',async()=>{
  const app=await fixture();try{
    const body={id,revision:version,action:'hide',notes:'Reviewed',confirm:id};
    assert.equal((await app.post('/api/action',{...body,confirm:mediaId},app.headers)).status,400);
    assert.equal((await app.post('/api/action',{...body,notes:''},app.headers)).status,400);
    assert.equal(app.calls.length,0);
    assert.equal((await app.post('/api/action',body,app.headers)).status,200);
    assert.equal(app.calls[0].path,'/rest/v1/rpc/review_content_report_checked');
    assert.equal(app.calls[0].body.p_revision,version);
    await app.post('/api/logout',{},app.headers);assert.equal((await app.post('/api/queue',{},app.headers)).status,401);
    assert.equal((await app.post('/session',{},app.headers)).status,401);
  }finally{await app.close();}
});
test('storage paths reject traversal, external URLs and unknown buckets; active formats rejected',()=>{
  for(const path of ['../secret','a/../secret','https://evil.example/a','a\\b','a//b','a/\0b'])assert.throws(()=>storagePath({bucket:'vault_photos',path}));
  assert.throws(()=>storagePath({bucket:'secrets',path:'a/b'}));
  assert.match(storagePath({bucket:'vault_photos',path:'a/photo space.png'}),/photo%20space.png$/);
  assert.throws(()=>mediaType(Buffer.from('<svg onload="evil()"/>'),'image'));
  assert.throws(()=>mediaType(Buffer.from('<html>'),'audio'));
  assert.equal(mediaType(png,'image'),'image/png');
  assert.deepEqual(Object.keys(publicCase(snapshot).media[0]),['id','kind']);
});
test('provider requests are fixed-origin, bounded, no-redirect and redact upstream errors',async()=>{
  let options;const backend=makeBackend('SECRET',async(url,args)=>{options=args;assert.ok(url.startsWith('https://vbzyvaylfdhwowdbodmk.supabase.co/'));return new Response(JSON.stringify({message:'private content SECRET'}),{status:500});});
  await assert.rejects(backend.request('/rest/v1/rpc/preview_content_report',{}),(e)=>!e.message.includes('SECRET'));
  assert.equal(options.redirect,'error');assert.ok(options.signal);
  await assert.rejects(readBounded((async function*(){yield Buffer.alloc(20);})(),10),/limit/);
});
test('retry is case-bound, ignores injected file paths, and refuses stale previews',async()=>{
  const app=await fixture();try{
    const response=await app.post('/api/retire',{id,revision:version,bucket:'secrets',source:'anything',destination:'anything'},app.headers);
    assert.equal(response.status,200);
    assert.ok(app.calls.every(c=>!JSON.stringify(c).includes('secrets')));
    assert.equal(app.calls[1].path,'/rest/v1/rpc/next_content_media_retirement');
    assert.deepEqual(app.calls[1].body,{p_report_id:id});
    const before=app.calls.length;
    assert.equal((await app.post('/api/retire',{id,revision:'b'.repeat(32)},app.headers)).status,409);
    assert.equal(app.calls.length,before+1);
  }finally{await app.close();}
});
