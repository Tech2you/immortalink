import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20260928212954_family_sponsorship.sql', import.meta.url), 'utf8');
const lifecycle = await readFile(new URL('../migrations/20260928223253_sponsorship_checkout_lifecycle.sql', import.meta.url), 'utf8');
const returning = await readFile(new URL('../migrations/20260929111512_returning_family_sponsor.sql', import.meta.url), 'utf8');
const isolation = await readFile(new URL('../migrations/20261001221344_apple_environment_isolation.sql', import.meta.url), 'utf8');
const retiredHistory = await readFile(new URL('../migrations/20261011205859_acknowledge_retired_apple_history.sql', import.meta.url), 'utf8');
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
const f = '00000000-0000-4000-8000-000000000003';
async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create table family_groups(id uuid primary key);
    create table family_members(family_id uuid,user_id uuid,role text);
    create table vaults(id uuid,owner_id uuid,display_name text,name text,created_at timestamptz);
    create table family_entitlements(family_id uuid primary key,plan text,status text,provider text,
      provider_entitlement_id text,provider_subscription_id text,billing_owner_user_id uuid references auth.users on delete set null,
      current_period_end timestamptz,apple_original_transaction_id text unique,apple_product_id text,apple_environment text,updated_at timestamptz);
    create table apple_subscription_events(family_id uuid,user_id uuid,event_source text,apple_environment text,
      apple_product_id text,apple_original_transaction_id text,apple_transaction_id text,notification_type text,entitlement_status text,raw_payload jsonb);
    insert into auth.users values('${a}'),('${b}');
    insert into family_groups values('${f}');
    insert into family_members values('${f}','${a}','owner'),('${f}','${b}','member');
    select set_config('test.uid','${b}',false);
  `);
  await db.exec(migration);
  await db.exec(lifecycle);
  await db.exec(returning);
  await db.exec(isolation);
  await db.exec(retiredHistory);
  return db;
}
function transaction(user=b, original='original-b', delta=0) {
  return { bundleId:'com.everroots.app',originalTransactionId:original,transactionId:`tx-${delta}`,
    appAccountToken:user,environment:'Sandbox',productId:'everroots.family.monthly',
    purchaseDate:Date.now()+delta,signedDate:Date.now()+delta,expiresDate:Date.now()+86400000 };
}
test('sandbox cannot overwrite an expired production family or bypass the public wrapper', async () => {
  const db=await fixture(); try {
    await db.query('select begin_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,{...transaction(),environment:'Production'})).applied,true);
    await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired'");
    const before=(await db.query('select * from family_entitlements')).rows;
    await assert.rejects(apply(db,transaction(b,'new-sandbox')),/APPLE_ENVIRONMENT_MISMATCH/);
    assert.deepEqual((await db.query('select * from family_entitlements')).rows,before);
    for (const role of ['anon','authenticated','service_role']) {
      assert.equal((await db.query("select has_function_privilege($1,'apply_verified_family_subscription_internal(jsonb,uuid,uuid,text,text)','execute') allowed",[role])).rows[0].allowed,false);
    }
  } finally { await db.close(); }
});
test('production purchase can replace expired sandbox coverage without changing purchaser binding rules', async () => {
  const db=await fixture(); try {
    await db.query('select begin_family_sponsorship($1)',[f]);
    await apply(db,transaction());
    await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired'; update family_sponsor_reservations set expires_at=now()-interval '1 second'");
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select begin_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,{...transaction(a,'production-a'),environment:'Production'},a)).applied,true);
    assert.equal((await db.query('select apple_environment from family_entitlements')).rows[0].apple_environment,'production');
    await assert.rejects(apply(db,{...transaction(a,'production-a'),environment:'Production'},b),/APPLE_PURCHASE_ALREADY_BOUND/);
  } finally { await db.close(); }
});
test('cancelled checkout releases only its own nonce; another member can then sponsor', async () => {
  const db=await fixture(); try {
    const first=(await db.query('select begin_family_sponsorship($1) as r',[f])).rows[0].r;
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select release_family_sponsorship($1,$2)',[f,first.reservation_id]);
    await assert.rejects(db.query('select begin_family_sponsorship($1)',[f]),/SPONSOR_PURCHASE_IN_PROGRESS/);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    await db.query('select release_family_sponsorship($1,$2)',[f,first.reservation_id]);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    const next=(await db.query('select begin_family_sponsorship($1) as r',[f])).rows[0].r;
    assert.notEqual(first.reservation_id,next.reservation_id);
    await db.query('select release_family_sponsorship($1,$2)',[f,first.reservation_id]);
    assert.equal((await db.query('select reservation_id from family_sponsor_reservations')).rows[0].reservation_id,next.reservation_id);
  } finally { await db.close(); }
});
test('verified purchase can recover after its expired checkout was replaced', async () => {
  const db=await fixture(); try {
    await db.query('select begin_family_sponsorship($1)',[f]);
    const tx=transaction();
    await db.exec("update family_sponsor_reservations set expires_at=now()-interval '1 second'");
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select begin_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,tx,b)).applied,true);
    assert.equal((await apply(db,transaction(a,'competing'),a)).code,'FAMILY_ALREADY_SPONSORED');
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id,b);
  } finally { await db.close(); }
});
test('checkout history is private, account-scoped and bounded by a burst limit', async () => {
  const db=await fixture(); try {
    for (let n=0;n<6;n++) {
      const r=(await db.query('select begin_family_sponsorship($1) as r',[f])).rows[0].r;
      await db.query('select release_family_sponsorship($1,$2)',[f,r.reservation_id]);
    }
    await assert.rejects(db.query('select begin_family_sponsorship($1)',[f]),/SPONSOR_CHECKOUT_RATE_LIMIT/);
    assert.equal((await db.query('select count(*)::int n from family_sponsor_reservations')).rows[0].n,0);
    assert.equal((await db.query("select has_table_privilege('authenticated','family_sponsor_checkout_attempts','select') allowed")).rows[0].allowed,false);
    assert.equal((await db.query("select has_function_privilege('authenticated','has_family_sponsorship_attempt(uuid,uuid,timestamptz)','execute') allowed")).rows[0].allowed,false);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select begin_family_sponsorship($1)',[f]);
  } finally { await db.close(); }
});
async function apply(db, tx, user=b, source='client_validation') {
  return (await db.query('select apply_verified_family_subscription($1,$2,$3,$4,null) as result',
    [JSON.stringify(tx),f,user,source])).rows[0].result;
}
test('ordinary member can reserve and sponsor without changing tree roles', async () => {
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,transaction())).applied,true);
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id,b);
    assert.equal((await db.query('select role from family_members where user_id=$1',[b])).rows[0].role,'member');
  } finally { await db.close(); }
});
test('reservation and active subscription reject a second sponsor',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await assert.rejects(db.query('select reserve_family_sponsorship($1)',[f]),/SPONSOR_PURCHASE_IN_PROGRESS/);
    await apply(db,transaction());
    await assert.rejects(db.query('select reserve_family_sponsorship($1)',[f]),/FAMILY_ALREADY_SPONSORED/);
  } finally { await db.close(); }
});
test('outsiders, token mismatch and unreserved first claims fail closed',async()=>{
  const db=await fixture(); try {
    assert.equal((await apply(db,transaction())).code,'APPLE_PURCHASER_UNVERIFIED');
    await db.query('select reserve_family_sponsorship($1)',[f]);
    await assert.rejects(apply(db,transaction(a)),/APPLE_PURCHASER_MISMATCH/);
    await assert.rejects(apply(db,transaction(f),f),/FAMILY_MEMBERSHIP_REQUIRED/);
    const {rows}=await db.query("select has_function_privilege('authenticated','apply_verified_family_subscription(jsonb,uuid,uuid,text,text)','execute') as allowed");
    assert.equal(rows[0].allowed,false);
    assert.equal((await db.query("select has_table_privilege('authenticated','apple_subscription_events','select') as allowed")).rows[0].allowed,false);
  } finally { await db.close(); }
});
test('expired sponsor can be replaced; previous renewal cannot reclaim family',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    await apply(db,transaction());
    await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired'; update family_sponsor_reservations set expires_at=now()-interval '1 second'");
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select reserve_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,transaction(a,'original-a'),a)).applied,true);
    assert.equal((await apply(db,transaction(b,'original-b',1000),null,'server_notification')).code,'APPLE_SPONSOR_REPLACED');
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id,a);
  } finally { await db.close(); }
});
test('older events cannot downgrade a newer renewal',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    const tx=transaction();
    await apply(db,tx);
    await apply(db,{...tx,purchaseDate:tx.purchaseDate+1000,signedDate:tx.signedDate+1000},null,'server_notification');
    assert.equal((await apply(db,{...tx,expiresDate:1},null,'server_notification')).code,'APPLE_EVENT_STALE');
    assert.equal((await db.query('select status from family_entitlements')).rows[0].status,'active');
  } finally { await db.close(); }
});

async function replacedSponsorFixture() {
  const db = await fixture();
  await db.query('select begin_family_sponsorship($1)', [f]);
  await apply(db, transaction());
  await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired'; update family_sponsor_reservations set expires_at=now()-interval '1 second'");
  await db.query("select set_config('test.uid',$1,false)", [a]);
  await db.query('select begin_family_sponsorship($1)', [f]);
  await apply(db, transaction(a, 'original-a'), a);
  await db.exec("update family_entitlements set current_period_end=now()-interval '1 second',status='expired'; update family_sponsor_reservations set expires_at=now()-interval '1 second'");
  await db.query("select set_config('test.uid',$1,false)", [b]);
  return db;
}

test('retired expired history clears original purchaser preflight without changing the family', async () => {
  const db = await replacedSponsorFixture(); try {
    const before = (await db.query('select * from family_entitlements')).rows;
    const expired = {...transaction(), expiresDate:1};
    const result = await apply(db, expired);
    assert.equal(result.code, 'APPLE_RETIRED_HISTORY');
    assert.equal(result.status, 'expired');
    assert.deepEqual((await db.query('select * from family_entitlements')).rows, before);
    assert.equal((await db.query("select retired from apple_sponsor_bindings where original_transaction_id='original-b'")).rows[0].retired, true);
    await assert.rejects(apply(db, expired, a), /APPLE_PURCHASE_ALREADY_BOUND/);
    await db.query('delete from family_members where user_id=$1', [b]);
    await assert.rejects(apply(db, expired), /FAMILY_MEMBERSHIP_REQUIRED/);
  } finally { await db.close(); }
});

test('retired expired history with a changed token is acknowledgement only for its recorded purchaser', async () => {
  const db = await replacedSponsorFixture(); try {
    const snapshot = async () => (await db.query(`select jsonb_build_object(
      'entitlements',(select jsonb_agg(to_jsonb(e)) from family_entitlements e),
      'bindings',(select jsonb_agg(to_jsonb(b) order by original_transaction_id) from apple_sponsor_bindings b),
      'events',(select jsonb_agg(to_jsonb(e)) from apple_subscription_events e),
      'reservations',(select jsonb_agg(to_jsonb(r)) from family_sponsor_reservations r)
    ) state`)).rows[0].state;
    const before = await snapshot();
    const expired = {...transaction(a, 'original-b', 1000), transactionId:'later-expired-history', expiresDate:1};
    const result = await apply(db, expired, b);
    assert.equal(result.applied, true);
    assert.equal(result.code, 'APPLE_RETIRED_HISTORY');
    assert.equal(result.status, 'expired');
    assert.equal(result.plan, 'free');
    assert.equal(result.product_id, expired.productId);
    assert.deepEqual(await snapshot(), before);
    assert.equal((await apply(db, expired, b)).code, 'APPLE_RETIRED_HISTORY');
    assert.deepEqual(await snapshot(), before);
    await assert.rejects(apply(db, expired, a), /APPLE_PURCHASE_ALREADY_BOUND/);
    await assert.rejects(db.query('select apply_verified_family_subscription($1,$2,$3,$4,null)',
      [JSON.stringify(expired), a, b, 'client_validation']), /APPLE_PURCHASE_ALREADY_BOUND/);
    await db.query('delete from family_members where user_id=$1', [b]);
    await assert.rejects(apply(db, expired, b), /FAMILY_MEMBERSHIP_REQUIRED/);
  } finally { await db.close(); }
});

test('history acknowledgement never authorizes mismatched active purchases or automatic sponsor replacement', async () => {
  const db = await replacedSponsorFixture(); try {
    const expired = {...transaction(a, 'original-b'), expiresDate:1};
    assert.equal((await apply(db, expired)).code, 'APPLE_RETIRED_HISTORY');
    assert.equal((await apply(db, expired, null, 'server_notification')).code, 'APPLE_SPONSOR_REPLACED');
    const fresh = {...transaction(a, 'original-b', 1000), transactionReason:'PURCHASE'};
    await db.query('select begin_family_sponsorship($1)', [f]);
    await assert.rejects(apply(db, fresh), /APPLE_PURCHASER_MISMATCH/);
    await assert.rejects(apply(db, {...expired, revocationDate:Date.now()}), /APPLE_PURCHASER_MISMATCH/);
    const corrected = {...fresh, appAccountToken:b};
    assert.equal((await apply(db, {...corrected, transactionReason:'RENEWAL'})).code, 'APPLE_SPONSOR_REPLACED');
    assert.equal((await apply(db, corrected)).applied, true);
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id, b);
  } finally { await db.close(); }
});

test('history acknowledgement stays blocked for unbound, non-retired, or production-isolated mismatches', async () => {
  const db = await replacedSponsorFixture(); try {
    const expired = {...transaction(a, 'original-b'), expiresDate:1};
    await assert.rejects(apply(db, {...expired, originalTransactionId:'unbound'}), /APPLE_PURCHASER_MISMATCH/);
    await db.exec("update apple_sponsor_bindings set retired=false where original_transaction_id='original-b'");
    await assert.rejects(apply(db, expired), /APPLE_PURCHASER_MISMATCH/);
    await db.exec("update apple_sponsor_bindings set retired=true where original_transaction_id='original-b'; update family_entitlements set apple_environment='production'");
    await assert.rejects(apply(db, expired), /APPLE_ENVIRONMENT_MISMATCH/);
    await db.exec("update family_entitlements set apple_environment='sandbox',status='active',current_period_end=now()+interval '1 day'");
    const before = (await db.query('select * from family_entitlements')).rows;
    await assert.rejects(apply(db, expired), /APPLE_PURCHASER_MISMATCH/);
    await assert.rejects(db.query('select begin_family_sponsorship($1)', [f]), /FAMILY_ALREADY_SPONSORED/);
    assert.deepEqual((await db.query('select * from family_entitlements')).rows, before);
  } finally { await db.close(); }
});

test('a returning sponsor needs a fresh checkout and customer-initiated purchase', async () => {
  const db = await replacedSponsorFixture(); try {
    const tx = {...transaction(b, 'original-b', 1000), transactionReason:'PURCHASE'};
    assert.equal((await apply(db, tx)).code, 'APPLE_SPONSOR_REPLACED');
    await db.query('select begin_family_sponsorship($1)', [f]);
    assert.equal((await apply(db, {...tx, transactionReason:'RENEWAL'})).code, 'APPLE_SPONSOR_REPLACED');
    assert.equal((await apply(db, tx, null, 'server_notification')).code, 'APPLE_SPONSOR_REPLACED');
    const tokenless = {...tx}; delete tokenless.appAccountToken;
    assert.equal((await apply(db, tokenless)).code, 'APPLE_SPONSOR_REPLACED');
    assert.equal((await apply(db, {...tx, purchaseDate:1})).code, 'APPLE_SPONSOR_REPLACED');
    assert.equal((await apply(db, tx)).applied, true);
    const entitlement = (await db.query('select * from family_entitlements')).rows[0];
    assert.equal(entitlement.billing_owner_user_id, b);
    assert.equal(entitlement.status, 'active');
    assert.equal((await db.query("select retired from apple_sponsor_bindings where original_transaction_id='original-b'")).rows[0].retired, false);
    assert.equal((await apply(db, transaction(a, 'original-a', 2000), null, 'server_notification')).code, 'APPLE_SPONSOR_REPLACED');
  } finally { await db.close(); }
});

test('returning sponsor cannot displace active coverage or use a released checkout', async () => {
  const db = await replacedSponsorFixture(); try {
    const reservation = (await db.query('select begin_family_sponsorship($1) r', [f])).rows[0].r;
    await db.query('select release_family_sponsorship($1,$2)', [f, reservation.reservation_id]);
    const tx = {...transaction(b, 'original-b', 1000), transactionReason:'PURCHASE'};
    assert.equal((await apply(db, tx)).code, 'APPLE_SPONSOR_REPLACED');
    await db.exec("update family_entitlements set current_period_end=now()+interval '1 day',status='active'");
    await assert.rejects(db.query('select begin_family_sponsorship($1)', [f]), /FAMILY_ALREADY_SPONSORED/);
    assert.equal((await apply(db, tx)).code, 'FAMILY_ALREADY_SPONSORED');
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id, a);
  } finally { await db.close(); }
});
test('deleted purchaser binding cannot be stolen; renewal retains paid family access',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    const tx=transaction(); await apply(db,tx);
    await db.query('delete from family_members where user_id=$1',[b]);
    await db.query('delete from auth.users where id=$1',[b]);
    await assert.rejects(apply(db,tx,a),/APPLE_PURCHASE_ALREADY_BOUND/);
    assert.equal((await apply(db,{...tx,purchaseDate:tx.purchaseDate+1000,signedDate:tx.signedDate+1000},null,'server_notification')).applied,true);
    assert.equal((await db.query('select billing_owner_user_id from family_entitlements')).rows[0].billing_owner_user_id,null);
  } finally { await db.close(); }
});

test('legacy tokenless restore requires its recorded purchaser and family',async()=>{
  const db=await fixture(); try {
    await db.query("insert into apple_sponsor_bindings(original_transaction_id,environment,purchaser_id,family_id) values('legacy','sandbox',$1,$2)",[b,f]);
    const tx=transaction(b,'legacy'); delete tx.appAccountToken;
    assert.equal((await apply(db,tx)).applied,true);
    await assert.rejects(apply(db,tx,a),/APPLE_PURCHASE_ALREADY_BOUND/);
    assert.equal((await apply(db,{...tx,originalTransactionId:'unbound'})).code,'APPLE_PURCHASER_UNVERIFIED');
  } finally { await db.close(); }
});

test('cancel intention alone preserves paid access; expiry and refund remove paid plan',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    const tx=transaction(); await apply(db,tx);
    const notify=async(t,type)=> (await db.query('select apply_verified_family_subscription($1,null,null,$2,$3) as result',
      [JSON.stringify(t),'server_notification',type])).rows[0].result;
    assert.equal((await notify({...tx,signedDate:tx.signedDate+1000},'DID_CHANGE_RENEWAL_STATUS')).status,'active');
    assert.equal((await notify({...tx,signedDate:tx.signedDate+2000,expiresDate:1},'EXPIRED')).status,'expired');
    assert.equal((await db.query('select plan from family_entitlements')).rows[0].plan,'free');
    assert.equal((await notify({...tx,signedDate:tx.signedDate+3000,revocationDate:Date.now()},'REFUND')).status,'refunded');
  } finally { await db.close(); }
});

test('sponsorship status excludes private data and is member-only',async()=>{
  const db=await fixture(); try {
    await db.query('select reserve_family_sponsorship($1)',[f]);
    await apply(db,transaction());
    await db.query('insert into vaults values($1,$2,$3,$3,now())',[b,b,'Sponsor']);
    const status=(await db.query('select get_family_sponsorship($1) as result',[f])).rows[0].result;
    assert.equal(status.active,true); assert.equal(status.sponsor_name,'Sponsor'); assert.equal(status.is_sponsor,true);
    assert.equal('original_transaction_id' in status,false);
    await db.query("select set_config('test.uid',$1,false)",[f]);
    await assert.rejects(db.query('select get_family_sponsorship($1)',[f]),/FAMILY_MEMBERSHIP_REQUIRED/);
  } finally { await db.close(); }
});

test('unmatched and delayed purchases leave private deduplicated recovery records',async()=>{
  const db=await fixture(); try {
    const tx=transaction();
    assert.equal((await apply(db,tx,null,'server_notification')).code,'APPLE_PURCHASE_UNMATCHED');
    await apply(db,tx,null,'server_notification');
    assert.equal((await db.query('select count(*)::int as n from apple_sponsorship_conflicts')).rows[0].n,1);
    assert.equal((await apply(db,tx)).code,'APPLE_PURCHASER_UNVERIFIED');
    assert.equal((await db.query('select count(*)::int as n from family_entitlements')).rows[0].n,0);
    assert.equal((await db.query("select has_table_privilege('authenticated','apple_sponsorship_conflicts','select') as allowed")).rows[0].allowed,false);
    assert.equal((await db.query("select has_function_privilege('authenticated','record_apple_sponsorship_conflict(jsonb,text,uuid,uuid)','execute') as allowed")).rows[0].allowed,false);
    await db.query('select reserve_family_sponsorship($1)',[f]);
    assert.equal((await apply(db,tx)).applied,true);
  } finally { await db.close(); }
});
