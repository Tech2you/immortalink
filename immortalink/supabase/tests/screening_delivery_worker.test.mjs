import {test} from 'node:test';
import assert from 'node:assert/strict';
import {deliveryFixture,issue,health} from './helpers/delivery_fixture.mjs';
import {flagged,inspected,decide} from './helpers/screening_review_fixture.mjs';
import {createHandler} from '../functions/send_screening_delivery/worker.mjs';
import {rpc as serviceRpc} from './helpers/screening_fixture.mjs';
import {memory,viewer,owner} from './helpers/retirement_fixture.mjs';
const args={claim_screening_delivery:['p_token'],authorize_screening_delivery:['p_id','p_lease'],
  finish_screening_delivery:['p_id','p_lease','p_result','p_retry_seconds']};
const request=token=>new Request('https://fixture.invalid',{method:'POST',headers:{'x-screening-delivery-token':token}});
test('actual staged SQL and delivery worker complete flag-email-approve-push using fake providers only',async t=>{
  const db=await deliveryFixture();t.after(()=>db.close());const sent=[];
  // Stand-in for pg_net: records requests locally and has no network capability.
  await db.exec(`create schema net;create table net.requests(id bigint generated always as identity,url text,headers jsonb,body jsonb,timeout_ms integer);
    create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language sql as $$
      insert into net.requests(url,headers,body,timeout_ms) values($1,$2,$3,$4) returning id; $$;`);
  const dispatch=async channel=>{
    const requestId=await serviceRpc(db,'dispatch_screening_delivery($1)',[channel]);
    if(requestId===null)return null;
    const row=(await db.query('select * from net.requests where id=$1',[requestId])).rows[0];
    assert.equal(row.url,'https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/send_screening_delivery');
    assert.deepEqual(row.body,{});assert.equal(row.timeout_ms,55000);
    assert.deepEqual(Object.keys(row.headers).sort(),['Content-Type','x-screening-delivery-token']);
    return row.headers['x-screening-delivery-token'];
  };
  assert.equal(await dispatch('email'),null);
  const handler=createHandler({enabled:true,serviceKey:'fixture',resendKey:'fixture',
    rpc:(name,body)=>serviceRpc(db,`${name}(${args[name].map((_,i)=>`$${i+1}`).join(',')})`,args[name].map(k=>body[k])),
    preparePush:async()=>({projectId:'fixture-project',accessToken:'fixture'}),
    fetcher:async(url,init)=>{
      assert(['https://api.resend.com/emails','https://fcm.googleapis.com/v1/projects/fixture-project/messages:send'].includes(url));
      sent.push({url,body:JSON.parse(init.body)});
      return Response.json(url.includes('resend')?{id:owner}:{name:'projects/fixture-project/messages/local'});
    }});
  const id=await flagged(db),token=await dispatch('email');
  assert.equal(await dispatch('email'),null);
  assert.equal((await handler(request(token))).status,200);assert.equal((await handler(request(token))).status,503);assert.equal(sent.length,1);
  assert(sent[0].body.text.includes(id));assert.equal(await issue(db,'push'),null);
  const data=await inspected(db,id);await decide(db,id,data.revision);
  assert.equal((await handler(request(await dispatch('push')))).status,200);assert.equal(sent.length,2);
  assert.equal((await health(db)).accepted,2);assert.equal(await issue(db,'push'),null);
  assert.equal(sent[1].body.message.token,'fixture-device-token');
  assert.equal(JSON.stringify(sent).includes('Reported memory'),false);
});
test('access changed during provider preparation suppresses push before any FCM request',async t=>{
  const db=await deliveryFixture();t.after(()=>db.close());const id=await flagged(db),data=await inspected(db,id);await decide(db,id,data.revision);
  const handler=createHandler({enabled:true,serviceKey:'fixture',
    rpc:(name,body)=>serviceRpc(db,`${name}(${args[name].map((_,i)=>`$${i+1}`).join(',')})`,args[name].map(k=>body[k])),
    preparePush:async()=>{await db.query('insert into member_blocks(blocker_id,blocked_id) values($1,$2)',[viewer,owner]);return {projectId:'fixture-project',accessToken:'fixture'};},
    fetcher:async()=>assert.fail('No FCM call permitted')});
  assert.deepEqual(await (await handler(request(await issue(db,'push')))).json(),{result:'NOT_ELIGIBLE'});
  assert.equal((await health(db)).push_attempts,0);
  assert.equal((await db.query('select id from memories where id=$1',[memory])).rows.length,1);
});
