import {test} from 'node:test';
import assert from 'node:assert/strict';
import {paidMoveFixture,moveFixture,move,used,usage,relocate,a,b,c,f,g,begin,tx,apply,limits,asUser,GB} from './helpers/contribution_move_fixture.mjs';
async function run(fn){const state=await paidMoveFixture();try{await fn(state)}finally{await state.db.close()}}
test('preview is read-only for benefits; confirm moves one grant and quota once, preserving content and ownership',()=>run(async({db,t})=>{
 await used(db,f,200,1800);await used(db,g,12,60);
 const before=(await db.query('select * from vaults order by owner_id')).rows;
 const members=(await db.query('select * from family_members order by family_id,user_id')).rows;
 const q=await move(db,t);assert.equal(q.ai_remaining,300);assert.equal(q.transcription_seconds_remaining,5400);
 assert.equal((await limits(db,f)).storage_bytes,5*GB);assert.equal((await limits(db,g)).storage_bytes,500*1024*1024);
 const result=await move(db,t,a,g,q.confirmation_id);assert.equal(result.moved,true);
 assert.equal((await limits(db,g)).storage_bytes,5*GB);assert.equal((await limits(db,f)).plan,'free');
 assert.deepEqual(await usage(db,g),{ai:212,seconds:1860});assert.deepEqual(await usage(db,f),{ai:0,seconds:0});
 assert.deepEqual(await move(db,t,a,g,q.confirmation_id),result);assert.deepEqual(await usage(db,g),{ai:212,seconds:1860});
 assert.deepEqual((await db.query('select * from vaults order by owner_id')).rows,before);
 assert.deepEqual((await db.query('select * from family_members order by family_id,user_id')).rows,members);
 assert.equal((await db.query('select count(*)::int n from family_entitlements')).rows[0].n,1);
 assert.equal((await db.query('select get_apple_contribution_move_candidate($1,$2,$3) r',[a,g,q.confirmation_id])).rows[0].r.original_id,t.originalTransactionId);
}));
test('other members/accounts, still-member payer, expired/refunded/mismatched receipts cannot move',()=>run(async({db,t})=>{
 for(const bad of [{...t,appAccountToken:b},{...t,expiresDate:Date.now()-1},{...t,revocationDate:Date.now()},{...t,bundleId:'evil'},{...t,environment:'Production'},{...t,productId:'other'}])await assert.rejects(move(db,bad),/APPLE_MOVE_/);
 await assert.rejects(move(db,t,b),/APPLE_MOVE_/);
 await db.query("insert into family_members values($1,$2,'member')",[f,a]);await assert.rejects(move(db,t),/APPLE_MOVE_/);
 await db.query('delete from family_members where family_id=$1 and user_id=$2',[f,a]);await db.query('delete from family_members where family_id=$1 and user_id=$2',[g,a]);await assert.rejects(move(db,t),/FAMILY_MEMBERSHIP_REQUIRED/);
}));
test('quote must be confirmed by same payer and family and becomes stale after usage or billing change',()=>run(async({db,t})=>{
 const q=await move(db,t);await used(db,f,1,1);await assert.rejects(move(db,t,a,g,q.confirmation_id),/APPLE_MOVE_STALE/);
 const q2=await move(db,t);await db.exec("update heiro_billing.contribution_move_quotes set expires_at=now()-interval '1 minute'");await assert.rejects(move(db,t,a,g,q2.confirmation_id),/APPLE_MOVE_STALE/);
 const q3=await move(db,t);await assert.rejects(move(db,t,a,f,q3.confirmation_id),/FAMILY_MEMBERSHIP_REQUIRED/);
 await db.exec("update apple_sponsor_bindings set retired=true");await assert.rejects(move(db,t,a,g,q3.confirmation_id),/APPLE_MOVE_UNAVAILABLE/);
}));
test('last-family deletion preserves remaining usage and grandfathered storage in a private billing record',()=>run(async({db,t})=>{
 await used(db,f,250,3600);await db.exec('update family_entitlements set storage_model_version=1');
 await db.query('delete from family_groups where id=$1',[f]);
 assert.equal((await db.query('select count(*)::int n from heiro_billing.detached_contributions')).rows[0].n,1);
 const q=await move(db,t);assert.equal(q.previous_family_exists,false);assert.equal(q.storage_bytes,10*GB);assert.equal(q.ai_remaining,250);
 await move(db,t,a,g,q.confirmation_id);assert.deepEqual(await usage(db,g),{ai:250,seconds:3600});assert.equal((await limits(db,g)).storage_bytes,10*GB);
 assert.equal((await db.query('select count(*)::int n from heiro_billing.detached_contributions')).rows[0].n,0);
}));
test('two contributors share prior usage proportionally, existing destination usage is retained',()=>run(async({db,t})=>{
 await begin(db,b);await apply(db,tx(b),b);await used(db,f,400,3600);
 const q=await move(db,t);assert.equal(q.ai_remaining,300);await move(db,t,a,g,q.confirmation_id);
 assert.deepEqual(await usage(db,f),{ai:200,seconds:1800});assert.deepEqual(await usage(db,g),{ai:200,seconds:1800});
 assert.equal((await limits(db,f)).storage_bytes,5*GB);
}));
test('moving back and forth does not reset exhausted quota or regenerate the free floor',()=>run(async({db,t})=>{
 await used(db,f,500,7200);
 for(let i=0;i<4;i++){
  const target=i%2===0?g:f,source=i%2===0?f:g;
  const q=await move(db,t,a,target);assert.equal(q.ai_remaining,0);assert.equal(q.transcription_seconds_remaining,0);
  await move(db,t,a,target,q.confirmation_id);const u=await usage(db,target);assert.ok(u.ai>=500);assert.ok(u.seconds>=7200);
  await relocate(db,a,target,source);
 }
}));
test('beta/manual access does not create quota by crediting usage on move',()=>run(async({db,t})=>{
 await db.query("insert into family_entitlements(family_id,plan,status,provider,current_period_end) values($1,'everroot_legacy','active','beta',now()+interval '7 days')",[f]);
 await used(db,f,900,12000);const q=await move(db,t);await move(db,t,a,g,q.confirmation_id);
 assert.deepEqual(await usage(db,f),{ai:900,seconds:12000});assert.deepEqual(await usage(db,g),{ai:300,seconds:3600});
}));
test('renewal and refund follow moved binding; stale old-family receipts cannot reclaim it',()=>run(async({db,t})=>{
 const q=await move(db,t);await move(db,t,a,g,q.confirmation_id);
 const renewed={...t,transactionId:'renewal',purchaseDate:t.purchaseDate+1000,signedDate:t.signedDate+1000,expiresDate:t.expiresDate+86400000};
 await apply(db,renewed,null,null,'server_notification');assert.equal((await limits(db,g)).storage_bytes,5*GB);
 await assert.rejects(apply(db,t,a,f),/FAMILY_MEMBERSHIP|PURCHASER_MISMATCH|PURCHASE_ALREADY_BOUND/);
 await apply(db,{...renewed,signedDate:renewed.signedDate+1000,revocationDate:Date.now()},null,null,'server_notification','REFUND');
 assert.equal((await limits(db,g)).plan,'free');
}));
test('clients cannot call move RPC or read private quotes; summary offer is only for payer in destination',()=>run(async({db,t})=>{
 await asUser(db,a);await db.exec('set role authenticated');
 assert.equal((await db.query('select get_family_sponsorship($1) r',[g])).rows[0].r.can_move_contribution,true);
 await assert.rejects(move(db,t),/permission denied/);
 await assert.rejects(db.query('select * from heiro_billing.contribution_move_quotes'),/permission denied/);
 await db.exec('reset role');await asUser(db,c);assert.equal((await db.query('select get_family_sponsorship($1) r',[g])).rows[0].r.can_move_contribution,false);
}));
test('normal AI/transcription consumption uses the moved family allowance and its existing membership guard',()=>run(async({db,t})=>{
 await used(db,f,499,7199);const q=await move(db,t);await move(db,t,a,g,q.confirmation_id);await asUser(db,a);
 assert.equal((await db.query('select everroot_consume_ai_usage($1,null,1) r',[g])).rows[0].r.remaining,0);
 await assert.rejects(db.query('select everroot_consume_ai_usage($1,null,1)',[g]),/ERR_EVERROOT_AI_LIMIT/);
 assert.equal((await db.query('select everroot_consume_transcription_usage($1,null,1) r',[g])).rows[0].r.remaining_seconds,0);
 await asUser(db,b);await assert.rejects(db.query('select everroot_consume_ai_usage($1,null,1)',[g]),/not a member/);
}));
test('renewals and refunds while the old family is deleted update only the private billing record',()=>run(async({db,t})=>{
 await used(db,f,100,600);await db.query('delete from family_groups where id=$1',[f]);
 const renewed={...t,transactionId:'detached-renewal',purchaseDate:t.purchaseDate+1000,signedDate:t.signedDate+1000,expiresDate:t.expiresDate+86400000};
 await apply(db,renewed,null,null,'server_notification');const q=await move(db,renewed);assert.equal(q.ai_remaining,400);assert.equal(new Date(q.paid_until).getTime(),renewed.expiresDate);
 await apply(db,{...renewed,signedDate:renewed.signedDate+1000,revocationDate:Date.now()},null,null,'server_notification','REFUND');
 await assert.rejects(move(db,renewed,a,g,q.confirmation_id),/APPLE_MOVE_UNAVAILABLE/);
 assert.equal((await limits(db,g)).plan,'free');
}));
test('a pending checkout blocks a move and a month boundary requires new confirmation',()=>run(async({db,t})=>{
 const q=await move(db,t);await db.query("insert into family_sponsor_reservations(family_id,user_id,expires_at) values($1,$2,now()+interval '5 minutes')",[g,a]);
 await assert.rejects(move(db,t,a,g,q.confirmation_id),/SPONSOR_PURCHASE_IN_PROGRESS/);
 await db.exec('delete from family_sponsor_reservations');
 await db.exec("create or replace function everroot_period_start(p_at timestamptz default now()) returns date language sql stable as $$select (date_trunc('month',p_at)+interval '1 month')::date$$");
 await assert.rejects(move(db,t,a,g,q.confirmation_id),/APPLE_MOVE_STALE/);
}));
test('Apple move checks are capped before calling Apple and recover in the next window',()=>run(async({db})=>{
 for(let i=0;i<20;i++)await db.query('select get_apple_contribution_move_candidate($1,$2)',[a,g]);
 await assert.rejects(db.query('select get_apple_contribution_move_candidate($1,$2)',[a,g]),/APPLE_MOVE_RATE_LIMIT/);
 await db.exec("update heiro_billing.contribution_move_checks set window_start=now()-interval '2 minutes'");
 assert.ok((await db.query('select get_apple_contribution_move_candidate($1,$2) r',[a,g])).rows[0].r);
}));
