import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {moveFixture,paidMoveFixture,move,used,usage,asUser,a,b,c,f,g,begin,tx,apply,limits,profilePoolMigration} from './helpers/contribution_move_fixture.mjs';
const read=n=>readFile(new URL(`../migrations/${n}.sql`,import.meta.url),'utf8');
const growth=await read('20261026080435_family_growth_admission_guards');
const guard=growth.match(/create or replace function public\.everroot_assert_legacy_person_capacity\(\)[\s\S]*?\n\$\$;/)[0];
const storageGuard=growth.match(/create (?:or replace )?function family_access\.assert_growth_storage\(p_family_id uuid\)[\s\S]*?\n\$\$;/)?.[0];
async function run(fn,options){const db=await moveFixture(options);try{await fn(db);}finally{await db.close();}}
async function pay(db,user=a,family=f,legacy=false){
 await begin(db,user,family);const t=tx(user,`chain-${user}`,legacy?{productId:'everroots.legacy.monthly'}:{});
 await apply(db,t,user,family);return t;
}
async function profileStore(db){
 await db.exec(`create table legacy_family_members(id uuid primary key default gen_random_uuid(),family_id uuid references family_groups(id),replaced_by_vault_id uuid);
 create schema if not exists family_access;
 create table test_media(family_id uuid primary key,bytes bigint);
 create function everroot_storage_bytes_used(p_family_id uuid,p_vault_id uuid) returns bigint language sql as $$select coalesce((select bytes from public.test_media where family_id=p_family_id),0)$$;
 create function everroot_limit_bigint(p_family_id uuid,p_metric text) returns bigint language sql as $$select (public.everroot_limits(p_family_id)->>p_metric)::bigint$$;
 create or replace function everroot_limit_int(p_family uuid,p_metric text) returns integer language sql as $$select (public.everroot_limits(p_family)->>p_metric)::integer$$;
 create function everroot_memory_count(uuid,uuid) returns integer language sql as $$select 0$$;
 create function everroot_photo_count(uuid,uuid) returns integer language sql as $$select 0$$;
 create function everroot_voice_note_count(uuid,uuid) returns integer language sql as $$select 0$$;
 create table everroot_invite_usage_periods(family_id uuid,period_start date,used_count integer);`);
 assert.ok(storageGuard,'Use the actual deployed full-storage admission check');
 await db.exec(storageGuard+'\n'+guard+`\ncreate trigger profile_capacity before insert or update of family_id,replaced_by_vault_id on legacy_family_members for each row execute function everroot_assert_legacy_person_capacity();`);
 await db.exec(await read('20260831122613_restore_family_usage_storage_rpc'));
 await db.exec(await read('20261031205918_legacy_profile_usage_counter'));
}
const add=(db,n,family=f)=>db.query('insert into legacy_family_members(family_id) select $1 from generate_series(1,$2)',[family,n]);
const count=async(db,family=f)=>Number((await db.query('select count(*) n from legacy_family_members where family_id=$1',[family])).rows[0].n);
const report=async(db,family=f)=>(await db.query('select get_family_entitlements_and_usage($1) r',[family])).rows[0].r;

test('free families receive 50 slots without a slot grant per real member',()=>run(async db=>{
 assert.equal((await limits(db)).legacy_people,50);
 await db.query("insert into family_members values($1,$2,'member')",[f,c]);
 assert.equal((await limits(db)).legacy_people,50);
}));
for(const [tiers,cap] of [[[false],100],[[true],500],[[false,false],200],[[false,true],600],[[true,true],1000]]){
 test(`${tiers.map(t=>t?'Legacy':'Family').join(' + ')} provides ${cap} slots without the free 50`,()=>run(async db=>{
  for(let i=0;i<tiers.length;i++)await pay(db,[a,b][i],f,tiers[i]);
  assert.equal((await limits(db)).legacy_people,cap);
 }));
}
test('renewal/replay do not grow slots; upgrade replaces the same contribution',()=>run(async db=>{
 const t=await pay(db);await apply(db,t);assert.equal((await limits(db)).legacy_people,100);
 const renewal={...t,transactionId:'renewed',transactionReason:'RENEWAL',signedDate:t.signedDate+100,purchaseDate:t.purchaseDate+100};
 await apply(db,renewal,null,null,'server_notification');assert.equal((await limits(db)).legacy_people,100);
 await apply(db,{...renewal,transactionId:'upgraded',productId:'everroots.legacy.monthly',signedDate:t.signedDate+200,purchaseDate:t.purchaseDate+200},null,null,'server_notification');
 assert.equal((await limits(db)).legacy_people,500);
}));
test('cancelled renewal keeps paid slots until expiry; refund removes only its own grant',()=>run(async db=>{
 const t=await pay(db);await pay(db,b,f,true);
 await db.query('update family_entitlements set cancel_at_period_end=true where billing_owner_user_id=$1',[a]);
 assert.equal((await limits(db)).legacy_people,600);
 await apply(db,{...t,signedDate:t.signedDate+100,revocationDate:Date.now()},null,null,'server_notification','REFUND');
 assert.equal((await limits(db)).legacy_people,500);
 await db.exec("update family_entitlements set current_period_end=now()-interval '1 second'");
 assert.equal((await limits(db)).legacy_people,50);
}));
test('migration changes only legacy slots, keeps privileges, preserves media and monthly allowances',()=>run(async db=>{
 await pay(db);await pay(db,b,f,true);
 const before=await limits(db);
 const security=()=>db.query("select oid::regprocedure::text name,proacl::text,prosecdef,proconfig from pg_proc where oid in ('everroot_limits(uuid)'::regprocedure,'heiro_billing.tier_limits(text)'::regprocedure) order by 1");
 const acl=await security();await db.exec(profilePoolMigration);
 assert.deepEqual(await limits(db),{...before,legacy_people:600});
 assert.deepEqual((await security()).rows,acl.rows);
 await db.exec('set role authenticated');await assert.rejects(limits(db),/permission denied/);
 await db.exec('reset role;set role anon');await assert.rejects(limits(db),/permission denied/);
}, {profilePool:false}));
test('full-storage admission still blocks new profiles with unused slots',()=>run(async db=>{
 await profileStore(db);await db.query('insert into test_media values($1,524288000)',[f]);
 await assert.rejects(add(db,1),/ERR_EVERROOT_STORAGE_LIMIT/);assert.equal(await count(db),0);
}));
test('counter, exact cap and retained rows agree for a large pooled family',()=>run(async db=>{
 await pay(db,a,f,true);await pay(db,b,f,true);await profileStore(db);await asUser(db,a);
 await add(db,999);await add(db,1);
 await db.query('update legacy_family_members set replaced_by_vault_id=$1 where id=(select id from legacy_family_members limit 1)',[a]);
 assert.equal((await report(db)).usage.legacy_people,1000);assert.equal((await report(db)).limits.legacy_people,1000);
 await assert.rejects(add(db,1),/ERR_EVERROOT_LEGACY_LIMIT/);assert.equal(await count(db),1000);
 // Downgrade/expiry retains every record, reports the lower cap, and blocks additions.
 await db.exec("update family_entitlements set current_period_end=now()-interval '1 second'");
 assert.equal((await report(db)).limits.legacy_people,50);assert.equal((await report(db)).usage.legacy_people,1000);
 await assert.rejects(add(db,1),/ERR_EVERROOT_LEGACY_LIMIT/);assert.equal(await count(db),1000);
 await assert.rejects(report(db,g),/not a member/);
 await asUser(db,null);await assert.rejects(report(db),/Not authenticated/);
}));
test('free last slot is allowed, the next blocked, deletion frees a slot',()=>run(async db=>{
 await profileStore(db);await add(db,50);await assert.rejects(add(db,1),/ERR_EVERROOT_LEGACY_LIMIT/);
 await db.exec('delete from legacy_family_members where id=(select id from legacy_family_members limit 1)');
 await add(db,1);assert.equal(await count(db),50);
}));
test('confirmed move transfers profile slots without resetting AI usage or altering real memberships',async()=>{
 const {db,t}=await paidMoveFixture();try{
  await used(db,f,10,60);const before=(await db.query('select * from family_members order by family_id,user_id')).rows;
  const q=await move(db,t);assert.equal((await limits(db,f)).legacy_people,100);assert.equal((await limits(db,g)).legacy_people,50);
  await move(db,t,a,g,q.confirmation_id);assert.equal((await limits(db,f)).legacy_people,50);assert.equal((await limits(db,g)).legacy_people,100);
  assert.deepEqual(await usage(db,g),{ai:10,seconds:60});assert.deepEqual((await db.query('select * from family_members order by family_id,user_id')).rows,before);
 }finally{await db.close();}
});
