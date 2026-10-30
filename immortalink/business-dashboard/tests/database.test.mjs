import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const {PGlite}=await import(pathToFileURL(process.env.PGLITE_MODULE||'/private/tmp/heiro-repurchase-tests/node_modules/@electric-sql/pglite/dist/index.js'));
const db=new PGlite();
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const month=new Date().toISOString().slice(0,7)+'-01';
await db.exec(`create role anon;create role authenticated;create role service_role;
create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,created_at timestamptz default now(),deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean default false);
create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
create table auth.mfa_factors(user_id uuid,status text);
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
create table public.family_groups(id uuid primary key,created_at timestamptz default now());
create table public.family_members(family_id uuid,user_id uuid);
create table public.family_entitlements(id uuid default gen_random_uuid(),family_id uuid,billing_owner_user_id uuid,plan text,status text,provider text,apple_environment text,current_period_end timestamptz,apple_original_transaction_id text);
create table public.apple_subscription_events(id uuid default gen_random_uuid(),family_id uuid,apple_environment text,apple_original_transaction_id text,entitlement_status text,raw_payload jsonb,created_at timestamptz default now());
create table storage.objects(metadata jsonb);
grant usage on schema public to anon,authenticated;
insert into auth.users(id,email) values('${id(1)}','owner@example.test'),('${id(2)}','member@example.test'),('${id(3)}','tester@example.test');
insert into auth.sessions(id,user_id) values('${id(101)}','${id(1)}'),('${id(102)}','${id(2)}');
insert into public.family_groups(id) values('${id(201)}'),('${id(202)}'),('${id(203)}'),('${id(204)}');
insert into public.family_members values('${id(201)}','${id(1)}'),('${id(202)}','${id(2)}'),('${id(203)}','${id(3)}'),('${id(204)}','${id(1)}');
insert into storage.objects values('{"size":1024}'),('{"size":"2048"}'),('{"size":"bad"}');`);
const migration=await readFile(new URL('../../supabase/migrations/20261030125715_private_business_dashboard.sql',import.meta.url),'utf8');
await db.exec(migration);
await db.query('insert into heiro_business.owners(user_id) values($1)',[id(1)]);
async function as(n,work,claims={}) {await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(n),session_id:id(100+n),aal:'aal1',...claims})]);await db.exec('set role authenticated');try{return await work();}finally{await db.exec('reset role');}}
const dashboard=async()=> (await db.query('select public.business_dashboard($1) as d',[month])).rows[0].d;
const add=entry=>db.query('select public.business_add_entry($1::jsonb)',[JSON.stringify(entry)]);
const entry={id:id(401),month,kind:'expense',category:'Supabase',reference:'Test invoice',currency:'USD',amount:25,zar_rate:18};
test('anonymous and family members cannot read or write business data',async()=>{await db.exec('set role anon');await assert.rejects(dashboard,/permission denied/);await db.exec('reset role');await as(2,async()=>{await assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/);await assert.rejects(()=>add(entry),/BUSINESS_ACCESS_DENIED/);await assert.rejects(()=>db.query('select * from heiro_business.entries'),/permission denied/);await assert.rejects(()=>db.query('select heiro_business.collect_metrics()'),/permission denied/);await assert.rejects(()=>db.query('select heiro_business.capture_daily()'),/permission denied/);});});
test('client metadata cannot grant admin and a forged session fails',async()=>{await as(2,async()=>assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/),{user_metadata:{role:'admin',is_owner:true}});await as(1,async()=>assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/),{session_id:id(999)});});
test('confirmed owner reads aggregates, not memory content',async()=>{await as(1,async()=>{const d=await dashboard();assert.equal(d.current.accounts,3);assert.equal(d.current.families,4);assert.equal(d.current.storage_bytes,3072);assert.equal(d.current.monthly_active_users,null);assert.equal(d.current.paying_contributors,0);assert.equal(d.report,null);assert.deepEqual(d.entries,[]);});});
test('paid counts exclude sandbox, zero-price offer, expired and unknown-price plans',async()=>{await db.exec(`insert into public.family_entitlements(family_id,billing_owner_user_id,plan,status,apple_environment,current_period_end,apple_original_transaction_id) values
('${id(201)}','${id(1)}','everroot_family','active','production',now()+interval '1 day','paid'),
('${id(202)}','${id(2)}','everroot_family','active','sandbox',now()+interval '1 day','sandbox'),
('${id(203)}','${id(3)}','everroot_legacy','active','production',now()+interval '1 day','trial'),
('${id(204)}','${id(1)}','everroot_family','active','production',now()+interval '1 day','unknown'),
('${id(202)}','${id(2)}','everroot_family','active','production',now()-interval '1 day','expired');
insert into public.apple_subscription_events(family_id,apple_environment,apple_original_transaction_id,entitlement_status,raw_payload) values
('${id(201)}','production','paid','active','{"price":119990}'),
('${id(201)}','production','paid','active','{"price":119990}'),
('${id(203)}','production','trial','active','{"price":0,"offerDiscountType":"FREE_TRIAL"}');`);await as(1,async()=>{const m=(await dashboard()).current;assert.equal(m.paying_contributors,1);assert.equal(m.funded_families,1);assert.equal(m.active_production_plans,3);assert.equal(m.free_offer_plans,1);assert.equal(m.unclassified_plans,1);});});
test('writes are durable, retries idempotent and conflicting retries rejected',async()=>{await as(1,async()=>{await add(entry);await add(entry);assert.equal((await dashboard()).entries.length,1);await assert.rejects(()=>add({...entry,amount:99}),/ENTRY_ID_ALREADY_USED/);await assert.rejects(()=>add({...entry,id:id(402),currency:'ZAR',zar_rate:18}),/check constraint/);});});
test('period source duplicate rejected across different assigned months',async()=>{await as(1,async()=>{await add({...entry,id:id(403),source_hash:'a'.repeat(64)});await assert.rejects(()=>add({...entry,id:id(404),source_hash:'a'.repeat(64)}),/unique constraint/);});});
test('monthly report validates churn and expenses reset completion',async()=>{await as(1,async()=>{const save=r=>db.query('select public.business_save_report($1::jsonb)',[JSON.stringify({month,reference:'Report',...r})]);await assert.rejects(()=>save({starting_payers:10,lost_starting_payers:11}),/check constraint/);await assert.rejects(()=>save({starting_payers:10}),/check constraint/);await save({starting_payers:10,lost_starting_payers:2,mrr_zar:1200,costs_complete:true});assert.equal((await dashboard()).report.costs_complete,true);await add({...entry,id:id(405)});assert.equal((await dashboard()).report.costs_complete,false);});});
test('exclusions change business aggregates, never app memberships or actual bytes',async()=>{await as(1,async()=>{await db.query('select public.business_set_exclusion($1,$2,$3,$4)',['account','tester@example.test','testing',true]);let m=(await dashboard()).current;assert.equal(m.accounts,2);assert.equal(m.families,3);assert.equal(m.storage_bytes,3072);await db.query('select public.business_set_exclusion($1,$2,$3,$4)',['account',id(3),'testing',false]);assert.equal((await dashboard()).current.accounts,3);});assert.equal((await db.query('select count(*)::int n from public.family_members')).rows[0].n,4);});
test('snapshots are one per UTC day, not fake historical activity',async()=>{await db.query('select heiro_business.capture_daily()');await db.query('select heiro_business.capture_daily()');assert.equal((await db.query('select count(*)::int n from heiro_business.snapshots')).rows[0].n,1);});
test('multi-currency import is atomic, retry-safe and rejects overlapping reports',async()=>{await as(1,async()=>{
  const first={...entry,id:id(420),kind:'apple_proceeds',category:'Apple',period_start:'2026-10-04',period_end:'2026-10-31',source_hash:'b'.repeat(64)};
  const second={...first,id:id(421),currency:'ZAR',zar_rate:18};
  const run=rows=>db.query('select public.business_import_proceeds($1::jsonb)',[JSON.stringify(rows)]);
  await assert.rejects(()=>run([first,second]),/check constraint/);
  assert.equal((await dashboard()).entries.some(e=>e.id===id(420)),false);
  second.zar_rate=1;await run([first,second]);await run([first,second]);
  assert.equal((await dashboard()).entries.filter(e=>e.source_hash==='b'.repeat(64)).length,2);
  await assert.rejects(()=>run([{...first,id:id(422),source_hash:'c'.repeat(64)}]),/OVERLAPPING_APPLE_REPORT/);
});});
test('MFA, banned accounts, revoked sessions and revoked ownership deny access',async()=>{await db.query("insert into auth.mfa_factors values($1,'verified')",[id(1)]);await as(1,async()=>assert.rejects(dashboard,/BUSINESS_MFA_REQUIRED/));await as(1,async()=>assert.equal((await dashboard()).current.accounts,3),{aal:'aal2'});await db.exec('delete from auth.mfa_factors');await db.query("update auth.users set banned_until=now()+interval '1 day' where id=$1",[id(1)]);await as(1,async()=>assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/));await db.query('update auth.users set banned_until=null where id=$1',[id(1)]);await db.query('delete from auth.sessions where id=$1',[id(101)]);await as(1,async()=>assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/));await db.query('insert into auth.sessions(id,user_id) values($1,$2)',[id(101),id(1)]);await db.query('delete from heiro_business.owners');await as(1,async()=>assert.rejects(dashboard,/BUSINESS_ACCESS_DENIED/));});
test.after(async()=>{await db.close();});
