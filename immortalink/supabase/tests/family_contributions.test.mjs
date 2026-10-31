import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture,bucketMigration,a,b,c,f,g,begin,tx,apply,limits,asUser,GB} from './helpers/family_contributions_fixture.mjs';
async function run(fn,options){const db=await fixture(options);try{await fn(db);}finally{await db.close();}}
const snapshot=async db=>(await db.query('select * from family_entitlements order by id')).rows;
test('free family has 500 MB once, two members each add 5 GB with no free top-up',()=>run(async db=>{
 assert.equal((await limits(db)).storage_bytes,500*1024*1024);
 await begin(db,a);assert.equal((await apply(db,tx())).applied,true);
 assert.equal((await limits(db)).storage_bytes,5*GB);
 await begin(db,b);assert.equal((await apply(db,tx(b),b)).applied,true);
 assert.equal((await limits(db)).storage_bytes,10*GB);
 assert.equal((await db.query('select count(*)::int n from apple_sponsor_bindings where not retired')).rows[0].n,2);
 assert.equal((await db.query('select count(*)::int n from family_entitlements')).rows[0].n,2);
}));
test('Family + Legacy pool 30 GB and additive monthly allowances; admission caps unchanged',()=>run(async db=>{
 await begin(db,a);await apply(db,tx());await begin(db,b);await apply(db,tx(b,'legacy',{productId:'everroots.legacy.annual'}),b);
 const l=await limits(db);assert.equal(l.storage_bytes,30*GB);assert.equal(l.ai_responses_monthly,2000);assert.equal(l.transcription_seconds_monthly,31200);
 assert.equal(l.legacy_people,250);assert.equal(l.real_members,null);assert.equal(l.invites_hourly_per_member,20);assert.equal(l.invites_hourly_per_family,50);
}));
test('renewals, replays and restore do not add a second allocation',()=>run(async db=>{
 await begin(db);const t=tx();await apply(db,t);await apply(db,t);await apply(db,{...t,transactionId:'renewal',transactionReason:'RENEWAL',purchaseDate:t.purchaseDate+1,signedDate:t.signedDate+1},null,null,'server_notification');
 assert.equal((await limits(db)).storage_bytes,5*GB);assert.equal((await snapshot(db)).length,1);
}));
test('upgrade replaces just that contribution, then expiry leaves the other payer intact',()=>run(async db=>{
 await begin(db,a);const first=tx();await apply(db,first);await begin(db,b);await apply(db,tx(b),b);
 await apply(db,{...first,productId:'everroots.legacy.monthly',transactionId:'upgrade',purchaseDate:first.purchaseDate+10,signedDate:first.signedDate+10},null,null,'server_notification');
 assert.equal((await limits(db)).storage_bytes,30*GB);
 await db.query("update family_entitlements set current_period_end=now()-interval '1 second' where billing_owner_user_id=$1",[a]);
 assert.equal((await limits(db)).storage_bytes,5*GB);
 await db.exec("update family_entitlements set current_period_end=now()-interval '1 second'");assert.equal((await limits(db)).storage_bytes,500*1024*1024);
}));
test('refund removes only its chain, stale notifications cannot downgrade current coverage',()=>run(async db=>{
 await begin(db,a);const t=tx();await apply(db,t);await begin(db,b);await apply(db,tx(b),b);
 await apply(db,{...t,transactionId:'renewal',transactionReason:'RENEWAL',purchaseDate:t.purchaseDate+100,signedDate:t.signedDate+100},null,null,'server_notification');
 const before=await snapshot(db);assert.equal((await apply(db,t,null,null,'server_notification')).code,'APPLE_EVENT_STALE');assert.deepEqual(await snapshot(db),before);
 await apply(db,{...t,transactionId:'renewal',purchaseDate:t.purchaseDate+100,signedDate:t.signedDate+200,revocationDate:Date.now()},null,null,'server_notification','REFUND');assert.equal((await limits(db)).storage_bytes,5*GB);
}));
test('one chain cannot fund two users or families, even within the same family',()=>run(async db=>{
 await begin(db);const t=tx();await apply(db,t);const before=await snapshot(db);
 await assert.rejects(()=>apply(db,t,b),/APPLE_PURCHASE_ALREADY_BOUND/);await assert.rejects(()=>apply(db,t,c,g),/APPLE_PURCHASE_ALREADY_BOUND/);
 assert.deepEqual(await snapshot(db),before);
}));
test('no membership, forged token, old receipt or anonymous caller can create a contribution',()=>run(async db=>{
 await assert.rejects(()=>begin(db,c),/FAMILY_MEMBERSHIP_REQUIRED/);
 const result=await apply(db,tx());assert.equal(result.code,'APPLE_PURCHASER_UNVERIFIED');
 await begin(db);await assert.rejects(()=>apply(db,tx(b)),/APPLE_PURCHASER_MISMATCH/);
 await db.exec('set role authenticated');await assert.rejects(()=>apply(db,tx()),/permission denied/);await assert.rejects(()=>db.query("insert into family_entitlements(family_id,plan) values($1,'everroot_legacy')",[f]),/permission denied/);await db.exec('reset role;set role anon');await assert.rejects(()=>db.query('select begin_family_storage_contribution($1)',[f]),/permission denied/);await db.exec('reset role');
}));
test('per-member checkouts and cancellation cannot replace another member reservation',()=>run(async db=>{
 const ar=await begin(db,a),br=await begin(db,b);assert.notEqual(ar.reservation_id,br.reservation_id);
 assert.equal((await begin(db,a)).reservation_id,ar.reservation_id);
 await asUser(db,b);await db.query('select release_family_sponsorship($1,$2)',[f,ar.reservation_id]);
 assert.equal((await db.query('select count(*)::int n from family_sponsor_reservations')).rows[0].n,2);
 await db.query('select release_family_sponsorship($1,$2)',[f,br.reservation_id]);assert.equal((await db.query('select count(*)::int n from family_sponsor_reservations')).rows[0].n,1);
}));
test('old app checkouts retain 10 GB, existing subscription survives migration and renewal',()=>run(async db=>{
 const hold=await begin(db,a,f,true);const t=tx();await apply(db,t);await db.query('select release_family_sponsorship($1,$2)',[f,hold.reservation_id]);await db.exec(bucketMigration);
 assert.equal((await limits(db)).storage_bytes,10*GB);
 await apply(db,{...t,transactionId:'renewal',purchaseDate:t.purchaseDate+100,signedDate:t.signedDate+100},null,null,'server_notification');assert.equal((await limits(db)).storage_bytes,10*GB);
 await begin(db,b);await apply(db,tx(b),b);assert.equal((await limits(db)).storage_bytes,15*GB);
},{bucket:false}));
test('old clients cannot start a second family purchase; new clients can contribute',()=>run(async db=>{
 await begin(db);await apply(db,tx());await assert.rejects(()=>begin(db,b,f,true),/APP_UPDATE_REQUIRED/);
 await begin(db,b);await apply(db,tx(b),b);assert.equal((await limits(db)).storage_bytes,10*GB);
}));
test('contributor summary exposes names and own plan, never Apple IDs or other-account management',()=>run(async db=>{
 await begin(db);await apply(db,tx());await asUser(db,b);const d=(await db.query('select get_family_sponsorship($1) r',[f])).rows[0].r;
 assert.equal(d.bucket_model,true);assert.equal(d.contributor_count,1);assert.equal(d.is_sponsor,false);assert.equal(d.own_plan,null);assert.equal(d.contributors[0].name,'Alex');
 assert.equal(JSON.stringify(d).includes('chain-'),false);assert.equal(JSON.stringify(d).includes(a),false);
 await asUser(db,c);await assert.rejects(()=>db.query('select get_family_sponsorship($1)',[f]),/FAMILY_MEMBERSHIP_REQUIRED/);
}));
test('leaving or deleting payer does not transfer the subscription or delete paid family coverage',()=>run(async db=>{
 await begin(db);const t=tx();await apply(db,t);await db.query('delete from family_members where user_id=$1',[a]);
 assert.equal((await limits(db)).storage_bytes,5*GB);await db.query('delete from auth.users where id=$1',[a]);
 await apply(db,{...t,transactionId:'renewal',purchaseDate:t.purchaseDate+100,signedDate:t.signedDate+100},null,null,'server_notification');assert.equal((await limits(db)).storage_bytes,5*GB);
 assert.equal((await snapshot(db))[0].billing_owner_user_id,null);
}));
test('production history rejects sandbox contamination',()=>run(async db=>{
 await begin(db);await apply(db,tx(a,'prod',{environment:'Production'}));await begin(db,b);
 await assert.rejects(()=>apply(db,tx(b),b),/APPLE_ENVIRONMENT_MISMATCH/);assert.equal((await limits(db)).storage_bytes,5*GB);
}));
test('authenticated members can start checkout but cannot call private helpers or write entitlements',()=>run(async db=>{
 await asUser(db,a);await db.exec('set role authenticated');
 assert.ok((await db.query('select begin_family_storage_contribution($1) r',[f])).rows[0].r.reservation_id);
 await assert.rejects(()=>db.query('select heiro_billing.begin_contribution($1,true)',[f]),/permission denied/);
 await db.exec('reset role');
}));
test('a started legacy checkout is honored at advertised capacity after rollout, even if another contribution arrives first',()=>run(async db=>{
 await begin(db,a,f,true);const old=tx(a,'old-pending');await db.exec(bucketMigration);
 await db.query("update family_sponsor_reservations set expires_at=now()-interval '1 second'");
 await begin(db,b);await apply(db,tx(b),b);
 assert.equal((await apply(db,old)).status,'active');assert.equal((await limits(db)).storage_bytes,15*GB);
},{bucket:false}));
test('fully expired verified repurchase can change payer while a different family contributor stays active',()=>run(async db=>{
 await begin(db,a);let old=tx(a,'repurchase',{purchaseDate:Date.now()-1000});await apply(db,old);
 await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired';delete from family_sponsor_reservations");
 await begin(db,b);const other=tx(b,'other');await apply(db,other,b);
 await db.query('insert into family_members values($1,$2,$3)',[f,c,'member']);
 await db.query("insert into family_entitlements(family_id,plan,status,provider,billing_owner_user_id,current_period_end) values($1,'everroot_family','active','testflight_beta_auto',$2,now()+interval '1 day')",[f,c]);
 old={...old,expiresDate:Date.now()-500};
 assert.equal((await db.query('select prepare_verified_apple_repurchase($1,$2,$3) r',[JSON.stringify(old),f,c])).rows[0].r.code,'APPLE_EXPIRED_HISTORY');
 await begin(db,c);await new Promise(r=>setTimeout(r,5));
 const fresh=tx(c,'repurchase',{transactionId:'repurchase-new'});
 for(const patch of [{transactionReason:'RENEWAL'},{appAccountToken:a},{purchaseDate:old.purchaseDate},{transactionId:old.transactionId}])
   await assert.rejects(()=>apply(db,{...fresh,...patch},c),/APPLE_PURCHASE_ALREADY_BOUND/);
 assert.equal((await apply(db,fresh,null,null,'server_notification')).code,'APPLE_PURCHASER_MISMATCH');
 assert.equal((await apply(db,fresh,c)).status,'active');assert.equal((await limits(db)).storage_bytes,10*GB);
 assert.equal((await db.query('select retired from apple_sponsor_bindings where original_transaction_id=$1',['other'])).rows[0].retired,false);
 const before=await snapshot(db);assert.equal((await apply(db,old,a)).code,'APPLE_EVENT_PREVIOUS_SPONSOR');assert.deepEqual(await snapshot(db),before);
}));
test('one payer cannot double-count distinct active Apple chains or sponsor another family',()=>run(async db=>{
 await begin(db,a);await apply(db,tx());
 const out=await apply(db,tx(a,'second-chain'));assert.equal(out.code,'FAMILY_ALREADY_SPONSORED');
 await db.exec('delete from family_sponsor_reservations');
 await db.query('insert into family_members values($1,$2,$3)',[g,a,'member']);
 await assert.rejects(()=>begin(db,a,g),/SPONSOR_ALREADY_SUPPORTS_FAMILY/);assert.equal((await limits(db)).storage_bytes,5*GB);
}));
test('checkout rate cap is per payer and release preserves other payer reservations',()=>run(async db=>{
 for(let i=0;i<6;i++){const r=await begin(db,a);await db.query('select release_family_sponsorship($1,$2)',[f,r.reservation_id]);}
 await assert.rejects(()=>begin(db,a),/SPONSOR_CHECKOUT_RATE_LIMIT/);assert.ok((await begin(db,b)).reservation_id);
}));
test('shared AI and transcription counters retain usage when contributions renew, join or expire',()=>run(async db=>{
 const {readFile}=await import('node:fs/promises');
 const source=async name=>readFile(new URL(`../migrations/${name}.sql`,import.meta.url),'utf8');
 const fn=(s,name)=>{const i=s.indexOf(`create or replace function public.${name}(`);assert.ok(i>=0);return s.slice(i,s.indexOf('\n$$;',i)+4);};
 const quota=await source('20260809100000_everroot_entitlements_and_quotas');
 const speech=await source('20260823224804_everroot_ai_transcription_cost_controls');
 await db.exec(`create table everroot_ai_usage_periods(scope_type text,scope_id uuid,period_start date,used_count integer,primary key(scope_type,scope_id,period_start));
 create table everroot_transcription_usage_periods(scope_type text,scope_id uuid,period_start date,used_seconds integer,primary key(scope_type,scope_id,period_start));
 create function everroot_limit_int(uuid,text) returns integer language sql stable as $$select (everroot_limits($1)->>$2)::integer$$;`);
 for(const name of ['everroot_period_start','everroot_quota_error','everroot_consume_ai_usage'])await db.exec(fn(quota,name));
 await db.exec(fn(speech,'everroot_consume_transcription_usage'));
 const ai=()=>db.query('select everroot_consume_ai_usage($1,null,1) r',[f]);
 const voice=()=>db.query('select everroot_consume_transcription_usage($1,null,1) r',[f]);
 await begin(db);const t=tx();await apply(db,t);
 await db.query("insert into everroot_ai_usage_periods values('family',$1,everroot_period_start(),499)",[f]);
 await db.query("insert into everroot_transcription_usage_periods values('family',$1,everroot_period_start(),7199)",[f]);
 assert.equal((await ai()).rows[0].r.used,500);assert.equal((await voice()).rows[0].r.used_seconds,7200);
 await assert.rejects(ai,/AI allowance/);await assert.rejects(voice,/transcription allowance/);
 await begin(db,b);await apply(db,tx(b),b);
 assert.equal((await ai()).rows[0].r.used,501);assert.equal((await voice()).rows[0].r.used_seconds,7201);
 await apply(db,{...t,transactionId:'renewal',signedDate:t.signedDate+100,purchaseDate:t.purchaseDate+100},null,null,'server_notification');
 assert.equal((await ai()).rows[0].r.used,502);
 await db.query("update family_entitlements set current_period_end=now()-interval '1 second' where billing_owner_user_id=$1",[a]);
 await assert.rejects(ai,/AI allowance/);await assert.rejects(voice,/transcription allowance/);
 assert.equal((await db.query('select used_count from everroot_ai_usage_periods')).rows[0].used_count,502);
}));
test('temporary beta grants remain a floor and never count as an Apple contribution',()=>run(async db=>{
 await db.query("insert into family_entitlements(family_id,plan,status,provider,billing_owner_user_id,current_period_end) values($1,'everroot_family','active','testflight_beta_auto',$2,now()+interval '1 day')",[f,a]);
 await begin(db);await apply(db,tx());assert.equal((await limits(db)).storage_bytes,10*GB);
 const d=(await db.query('select get_family_sponsorship($1) r',[f])).rows[0].r;
 assert.equal(d.contributor_count,1);assert.equal(d.included_access_bytes,10*GB);
 await db.exec("update family_entitlements set current_period_end=now()-interval '1 second' where provider='testflight_beta_auto'");assert.equal((await limits(db)).storage_bytes,5*GB);
}));
test('former beta family allowance does not block a genuine contribution in the current family',()=>run(async db=>{
 await db.query("insert into family_entitlements(family_id,plan,status,provider,billing_owner_user_id,current_period_end) values($1,'everroot_family','active','testflight_beta_auto',$2,now()+interval '1 day')",[f,a]);
 await db.query('insert into family_members values($1,$2,$3)',[g,a,'member']);
 assert.ok((await begin(db,a,g)).reservation_id);
 assert.equal((await apply(db,tx(),a,g)).status,'active');assert.equal((await limits(db,g)).storage_bytes,5*GB);
}));
