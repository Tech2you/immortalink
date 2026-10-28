import {test} from 'node:test';
import assert from 'node:assert/strict';
import {startReviewServer} from './content_review_server.mjs';
const id='00000000-0000-4000-8000-000000000001',mediaId='00000000-0000-4000-8000-000000000002',revision='a'.repeat(32);
const item={id:mediaId,kind:'image',bucket:'vault_photos',path:'fixture/image.png',metadata:{eTag:'fixture'}};
const snapshot={report:{id,kind:'memory',status:'open'},available:true,fields:{Memory:'QA'},media:[item],revision};
const png=Buffer.from([137,80,78,71,13,10,26,10]);
async function fixture(screeningReview=true){
  const calls=[];
  const backend={request:async(path,body)=>{
    calls.push({path,body});if(path.includes('preview_screening_review'))return body.p_media_id?item:snapshot;
    if(path.includes('decide_screening_review'))return {id,action:body.p_action,status:'approved'};
    return [];
  },download:async()=>{calls.push({download:true});return png;}};
  const app=await startReviewServer({backend,reviewer:'QA',screeningReview});const origin=new URL(app.url).origin;
  const post=(path,body={},headers={})=>fetch(`${origin}${path}`,{method:'POST',headers:{origin,'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
  const session=await post('/session',{key:new URL(app.url).hash.slice(1)}),data=await session.json();
  return {...app,backend,calls,post,session:data,headers:{Cookie:session.headers.get('set-cookie').split(';')[0],'X-Review-CSRF':data.csrf}};
}
test('automatic review is default-off; existing report console makes no new backend calls',async()=>{
  const app=await fixture(false);try{
    assert.equal(app.session.screeningReview,false);
    assert.equal((await app.post('/api/screening/queue',{state:'active'},app.headers)).status,404);assert.deepEqual(app.calls,[]);
    assert.equal((await app.post('/api/screening/health',{},app.headers)).status,404);assert.deepEqual(app.calls,[]);
  }finally{await app.close();}
});
test('delivery health is session-bound and uses only its fixed service endpoint',async()=>{
  const app=await fixture();try{
    assert.equal((await app.post('/api/screening/health')).status,401);
    assert.equal((await app.post('/api/screening/health',{recipient:'attacker',action:'send'},app.headers)).status,200);
    assert.deepEqual(app.calls,[{path:'/rest/v1/rpc/screening_delivery_health',body:{}}]);
  }finally{await app.close();}
});
test('automatic queue and case are session-bound, redacted, and use separate service endpoints',async()=>{
  const app=await fixture();try{
    assert.equal((await app.post('/api/screening/queue',{state:'active'})).status,401);
    assert.equal((await app.post('/api/screening/queue',{state:'all'},app.headers)).status,400);
    await app.post('/api/screening/queue',{state:'held'},app.headers);
    assert.deepEqual(app.calls[0],{path:'/rest/v1/rpc/screening_review_queue',body:{p_state:'held'}});
    const data=await (await app.post('/api/screening/case',{id,reviewer:'attacker'},app.headers)).json();
    assert.equal(JSON.stringify(data).includes('fixture/image.png'),false);assert.deepEqual(data.media,[{id:mediaId,kind:'image'}]);
    assert.equal(app.calls[1].body.p_reviewer,'QA');
  }finally{await app.close();}
});
test('image preview checks twice and acknowledges only verified retrieval',async()=>{
  const app=await fixture();try{
    const response=await app.post('/api/screening/media',{id,mediaId,revision,path:'unrelated'},app.headers);
    assert.equal(response.status,200);assert.deepEqual(Buffer.from(await response.arrayBuffer()),png);
    assert.equal(app.calls.length,4);assert.equal(app.calls[1].download,true);
    assert.equal(app.calls[3].path,'/rest/v1/rpc/ack_screening_review_media');
    assert.ok(app.calls.every(c=>!JSON.stringify(c).includes('unrelated')));
  }finally{await app.close();}
});
test('failed, changed or unsupported media cannot be acknowledged',async t=>{
  for(const mode of ['failed','changed','active-format'])await t.test(mode,async()=>{
    const app=await fixture();try{
      let previews=0;const original=app.backend.request;
      app.backend.request=async(path,body)=>{const result=await original(path,body);if(path.includes('preview_screening_review') && ++previews===2 && mode==='changed')return {...item,path:'changed.png'};return result;};
      app.backend.download=async()=>{if(mode==='failed')throw Error('SECRET');return mode==='active-format'?Buffer.from('<svg onload=evil()>'):png;};
      const response=await app.post('/api/screening/media',{id,mediaId,revision},app.headers);assert.notEqual(response.status,200);
      assert.equal((await response.text()).includes('SECRET'),false);
      assert.equal(app.calls.some(c=>c.path?.includes('ack_screening')),false);
    }finally{await app.close();}
  });
});
test('check decisions cannot invoke report restore, suspension, retirement or injected identities',async()=>{
  const app=await fixture();try{
    const body={id,revision,action:'approve',notes:'Reviewed fixture',confirm:id};
    for(const action of ['restore','dismiss','suspend','hide'])assert.equal((await app.post('/api/screening/action',{...body,action},app.headers)).status,400);
    assert.equal((await app.post('/api/screening/action',{...body,confirm:mediaId},app.headers)).status,400);
    assert.equal((await app.post('/api/screening/action',{...body,notes:''},app.headers)).status,400);assert.equal(app.calls.length,0);
    assert.equal((await app.post('/api/screening/action',{...body,reviewer:'attacker',family:'anything'},app.headers)).status,200);
    assert.deepEqual(app.calls[0],{path:'/rest/v1/rpc/decide_screening_review',body:{p_case:id,p_reviewer:'QA',p_action:'approve',p_notes:'Reviewed fixture',p_revision:revision}});
  }finally{await app.close();}
});
