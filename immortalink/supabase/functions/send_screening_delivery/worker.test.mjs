import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {createHandler,makeRpc} from './worker.mjs';
import {emailPayload,pushPayload,prepareFirebase,sendDelivery,requestJson} from './transport.mjs';
const id='00000000-0000-4000-8000-000000000001',lease='00000000-0000-4000-8000-000000000002';
const now=()=>Date.parse('2026-10-24T12:00:00Z');
const grant=channel=>({id,channel,case_id:id,family_id:id,event_id:lease,token:'fixture-token',send_before:new Date(now()+15000).toISOString()});
const request=()=>new Request('https://fixture.invalid',{method:'POST',headers:{'x-screening-delivery-token':'a'.repeat(64)},body:JSON.stringify({to:'attacker',token:'untrusted'})});
const json=(data,status=200,headers={})=>new Response(JSON.stringify(data),{status,headers});
const credentials={resendKey:'fixture-resend',projectId:'fixture-project',accessToken:'fixture-access'};
test('disabled, unauthenticated and unconfigured requests cause no RPC or network activity',async()=>{
  const denied=()=>{assert.fail('Unexpected activity');};
  assert.equal((await createHandler({rpc:denied,fetcher:denied})(request())).status,503);
  const enabled=createHandler({enabled:true,rpc:denied,fetcher:denied});
  assert.equal((await enabled(new Request('https://fixture.invalid'))).status,405);
  assert.equal((await enabled(new Request('https://fixture.invalid',{method:'POST'}))).status,401);
  assert.equal((await enabled(request())).status,503);
});
test('worker obtains credentials before fresh authorization; caller payload cannot choose recipients',async()=>{
  for(const channel of ['email','push']){
    const calls=[];
    const handler=createHandler({enabled:true,serviceKey:'fixture-service',resendKey:'fixture-resend',now,
      preparePush:async()=>{calls.push('oauth');return credentials;},
      rpc:async(name,body)=>{
        calls.push(name);if(name==='claim_screening_delivery')return {id,lease,channel};
        if(name==='authorize_screening_delivery')return grant(channel);
        assert.equal(body.p_result,'ACCEPTED');return true;
      },fetcher:async(url,init)=>{
        calls.push('send');assert.equal(init.redirect,'error');assert.ok(init.signal);
        const body=JSON.parse(init.body);assert(!init.body.includes('attacker'));
        if(channel==='email'){
          assert.equal(url,'https://api.resend.com/emails');assert.deepEqual(body.to,['linebreakers@outlook.com']);
          assert.equal(init.headers['Idempotency-Key'],`screening-review/${id}/v1`);return json({id});
        }
        assert.equal(body.message.token,'fixture-token');assert.equal(body.message.data.event_id,lease);
        assert.equal(body.message.android.ttl,'0s');assert.equal(body.message.apns.headers['apns-expiration'],'0');
        return json({name:'projects/fixture-project/messages/example'});
      }});
    assert.deepEqual(await (await handler(request())).json(),{result:'ACCEPTED'});
    assert.deepEqual(calls,['claim_screening_delivery',...(channel==='push'?['oauth']:[]),'authorize_screening_delivery','send','finish_screening_delivery']);
  }
});
test('stale eligibility, malformed or expired grants never contact a delivery provider',async()=>{
  for(const mutation of [()=>null,g=>({...g,id:'wrong'}),g=>({...g,channel:'push'}),g=>({...g,case_id:'bad'}),
    g=>({...g,send_before:new Date(now()-1).toISOString()}),g=>({...g,send_before:new Date(now()+60000).toISOString()})]){
    const handler=createHandler({enabled:true,serviceKey:'fixture',resendKey:'fixture',now,
      rpc:async name=>name==='claim_screening_delivery'?{id,lease,channel:'email'}:mutation(grant('email')),
      fetcher:async()=>assert.fail('Unexpected provider call')});
    assert.match((await (await handler(request())).json()).result,/NOT_ELIGIBLE|INVALID_GRANT/);
  }
});
test('failed provider preparation does not consume dispatch budget; failed acknowledgements are explicit',async()=>{
  let calls=0;
  const base={enabled:true,serviceKey:'fixture',resendKey:'fixture',now,fetcher:async()=>json({id})};
  let handler=createHandler({...base,preparePush:async()=>{throw new Error('private credential detail');},
    rpc:async()=>{calls++;return {id,lease,channel:'push'};}});
  assert.deepEqual(await (await handler(request())).json(),{result:'PROVIDER_UNAVAILABLE'});assert.equal(calls,1);
  handler=createHandler({...base,rpc:async name=>{
    if(name==='claim_screening_delivery')return {id,lease,channel:'email'};
    if(name==='authorize_screening_delivery')return grant('email');throw new Error('private database detail');
  }});
  assert.deepEqual(await (await handler(request())).json(),{result:'ACK_UNCONFIRMED'});
});
test('payloads contain no memory text, media, author names or review session URLs',()=>{
  const data={...grant('push'),body:'PRIVATE_BODY',name:'PRIVATE_NAME',url:'PRIVATE_URL'};
  const email=JSON.stringify(emailPayload(id)),push=JSON.stringify(pushPayload(data));
  assert.equal(/PRIVATE_|127\.0\.0\.1|supabase\.co/.test(email+push),false);
  assert.equal(/case_id|screening|review/i.test(push),false);
  assert.throws(()=>emailPayload('invalid'));assert.throws(()=>pushPayload({...data,token:''}));
});
test('transport separates definite failures from ambiguous responses and honors provider backoff',async t=>{
  const cases=[['accepted',200,{id,name:'projects/fixture-project/messages/1'},'ACCEPTED'],
    ['malformed-success',200,{},'UNKNOWN'],['limit',429,{},'RETRY'],['server',503,{},'RETRY'],
    ['invalid',400,{},'REJECTED'],['unauthorized',401,{},'REJECTED'],['redirect',302,{},'REJECTED']];
  for(const [name,status,data,result] of cases)await t.test(name,async()=>{
    for(const channel of ['email','push']){
      const actual=await sendDelivery(grant(channel),credentials,async()=>json(data,status,{'retry-after':'600'}),now);
      assert.equal(actual.result,result);if(result==='RETRY')assert.equal(actual.retrySeconds,600);
    }
  });
  assert.equal((await sendDelivery(grant('push'),credentials,async()=>{throw new Error('private echo');},now)).result,'UNKNOWN');
  assert.equal((await sendDelivery(grant('email'),credentials,async()=>json({},409),now)).result,'RETRY');
  assert.equal((await sendDelivery(grant('push'),credentials,async()=>json({},409),now)).result,'REJECTED');
  assert.equal((await sendDelivery(grant('push'),credentials,async()=>json({},503,{'retry-after':new Date(now()+120000).toUTCString()}),now)).retrySeconds,120);
});
test('bounded responses and timeout prevent open-ended provider and database reads',async()=>{
  await assert.rejects(requestJson(async()=>new Response('x'.repeat(32769)),'https://fixture.invalid',{}),/LIMIT/);
  await assert.rejects(requestJson(async()=>new Response('{}',{headers:{'content-length':'40000'}}),'https://fixture.invalid',{}),/LIMIT/);
  await assert.rejects(requestJson(async(_url,init)=>new Promise((_resolve,reject)=>init.signal.addEventListener('abort',()=>reject(new Error('timeout')))),
    'https://fixture.invalid',{},5),/timeout/);
  const rpc=makeRpc('fixture',async(url,init)=>{assert(url.startsWith('https://vbzyvaylfdhwowdbodmk.supabase.co/rest/v1/rpc/'));assert.equal(init.redirect,'error');return json(null);});
  assert.equal(await rpc('authorize_screening_delivery',{}),null);
  await assert.rejects(rpc('delete_account',{}),/DENIED/);
});
test('Firebase credential exchange uses fixed endpoint, narrow scope and an actual local RSA signature',async()=>{
  const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048});
  const account={project_id:'fixture-project',client_email:'worker@fixture-project.iam.gserviceaccount.com',
    private_key:privateKey.export({type:'pkcs8',format:'pem'}),token_uri:'https://attacker.invalid'};
  const result=await prepareFirebase(JSON.stringify(account),async(url,init)=>{
    assert.equal(url,'https://oauth2.googleapis.com/token');assert.equal(init.redirect,'error');
    const [header,payload,signature]=init.body.get('assertion').split('.');
    const claims=JSON.parse(Buffer.from(payload,'base64url'));
    assert.equal(claims.scope,'https://www.googleapis.com/auth/firebase.messaging');assert.equal(claims.exp-claims.iat,3600);
    const key=await crypto.subtle.importKey('spki',publicKey.export({type:'spki',format:'der'}),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
    assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,Buffer.from(signature,'base64url'),new TextEncoder().encode(`${header}.${payload}`)),true);
    return json({access_token:'local-fake-access',token_type:'Bearer',expires_in:3600});
  },now);
  assert.deepEqual(result,{projectId:'fixture-project',accessToken:'local-fake-access'});
  await assert.rejects(prepareFirebase(JSON.stringify({...account,project_id:'../other'}),async()=>assert.fail('network')));
  await assert.rejects(prepareFirebase(JSON.stringify(account),async()=>json({access_token:'fake',expires_in:1})));
});
