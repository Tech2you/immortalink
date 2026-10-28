import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { growthFixture, growthMigration, setBytes } from './helpers/family_growth_fixture.mjs';
import { user, ownerA, ownerB, familyA, familyB, vault } from './helpers/single_family_fixture.mjs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const cap = 524288000;
const member = (db,id=randomUUID(),family=familyA) => db.query(
  "insert into family_members(family_id,user_id,role) values($1,$2,'member')",[family,id]);
const invite = (db,{actor=ownerA,family=familyA,email=null,phone=null,created=null}={}) => db.query(
  `insert into family_invites(family_id,created_by,invite_code,expires_at,recipient_email,recipient_phone,created_at)
    values($1,$2,$3,now()+interval '1 day',$4,$5,coalesce($6,now())) returning id,created_at`,
  [family,actor,randomUUID(),email,phone,created]);
const legacy = (db,family=familyA,replaced=null) => db.query(
  'insert into legacy_family_members(family_id,replaced_by_vault_id) values($1,$2) returning id',[family,replaced]);
const errorCode = e => e.detail?.startsWith('ERR_EVERROOT_') ? e.detail : e.message;
const rejectsCode = (promise,code) => assert.rejects(promise,e=>errorCode(e)===code);
async function fixture(options) { const db=new PGlite(); await growthFixture(db,options); return db; }
async function run(fn,options) { const db=await fixture(options); try{await fn(db);}finally{await db.close();} }
const ageEvents = db => db.exec("update family_access.invite_rate_events set created_at=clock_timestamp()-interval '1 minute'");

test('unlimited real totals preserve all other plan benefits',()=>run(async db=>{
  const before={};
  for(const plan of ['free','everroot_family','everroot_legacy']) {
    await db.query('insert into family_entitlements values($1,$2) on conflict(family_id) do update set plan=excluded.plan',[familyA,plan]);
    before[plan]=(await db.query('select everroot_limits($1) as value',[familyA])).rows[0].value;
  }
  await db.exec(growthMigration);
  for(const plan of Object.keys(before)) {
    await db.query('update family_entitlements set plan=$1 where family_id=$2',[plan,familyA]);
    const after=(await db.query('select everroot_limits($1) as value',[familyA])).rows[0].value;
    assert.equal(after.real_members,null); assert.equal(after.invites_monthly,null);
    assert.equal(after.invites_hourly_per_member,20); assert.equal(after.invites_hourly_per_family,50);
    for(const key of Object.keys(before[plan]).filter(k=>!['real_members','invites_monthly'].includes(k)))
      assert.deepEqual(after[key],before[plan][key],`${plan}.${key}`);
  }
  await db.query("update family_entitlements set plan='free'");
  for(let i=0;i<40;i++) await member(db);
  assert.equal((await db.query('select count(*)::int as n from family_members where family_id=$1',[familyA])).rows[0].n,41);
  assert.equal((await db.query('select everroot_family_is_read_only($1) as ro',[familyA])).rows[0].ro,false);
},{migrate:false}));

test('at or above full storage blocks invites, real admissions and legacy profiles, not existing edits',()=>run(async db=>{
  for(const bytes of [cap,cap+1]) {
    await setBytes(db,bytes);
    await assert.rejects(invite(db),e=>['ERR_EVERROOT_STORAGE_LIMIT','ERR_EVERROOT_READ_ONLY'].includes(errorCode(e)));
    // Above-cap free families also retain the existing read-only error.
    await assert.rejects(member(db),e=>['ERR_EVERROOT_STORAGE_LIMIT','ERR_EVERROOT_READ_ONLY'].includes(errorCode(e)));
    await assert.rejects(legacy(db),e=>['ERR_EVERROOT_STORAGE_LIMIT','ERR_EVERROOT_READ_ONLY'].includes(errorCode(e)));
    await db.query('select everroot_assert_can_add_family_member($1,$2)',[familyA,ownerA]);
    await db.query("update family_members set role='owner' where family_id=$1 and user_id=$2",[familyA,ownerA]);
  }
  await setBytes(db,cap-1);
  await member(db); await legacy(db); await invite(db);
}));

test('incoming private media must fit in remaining family storage',()=>run(async db=>{
  await setBytes(db,cap-5);
  await db.query('insert into storage.objects values($1,$2,$3)',
    ['memory_photos',`${user}/${vault}/private.jpg`,JSON.stringify({size:6})]);
  await rejectsCode(member(db,user),'ERR_EVERROOT_STORAGE_LIMIT');
  await db.exec("update storage.objects set metadata='{"+'"size":5'+"}'::jsonb where name like '%private.jpg'");
  await member(db,user);
  assert.equal((await db.query('select everroot_storage_bytes_used($1,null) as used',[familyA])).rows[0].used,cap);
}));

for(const rpc of ['join_family_by_relationship_invite','join_family_by_invite']) {
  test(`${rpc} checks storage at acceptance and leaves rejected invite usable`,()=>run(async db=>{
    const created=await invite(db);
    const code=(await db.query('select invite_code from family_invites where id=$1',[created.rows[0].id])).rows[0].invite_code;
    await setBytes(db,cap);
    await db.query("select set_config('test.uid',$1,false)",[user]);
    await db.exec('set role authenticated');
    await rejectsCode(db.query(`select ${rpc}($1)`,[code]),'ERR_EVERROOT_STORAGE_LIMIT');
    await db.exec('reset role');
    assert.equal((await db.query('select used_at from family_invites where id=$1',[created.rows[0].id])).rows[0].used_at,null);
    assert.equal((await db.query('select count(*)::int as n from family_members where user_id=$1',[user])).rows[0].n,0);
    await setBytes(db,0);
    await db.exec('set role authenticated');
    await db.query(`select ${rpc}($1)`,[code]);
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int as n from family_members where user_id=$1',[user])).rows[0].n,1);
  }));
}

test('single-family rule still blocks joining an additional family',()=>run(async db=>{
  await member(db,user);
  await rejectsCode(member(db,user,familyB),'FAMILY_MEMBERSHIP_LIMIT');
}));

test('legacy limits bound retained profiles and guard moves while allowing existing name edits',()=>run(async db=>{
  const ids=[];
  for(let i=0;i<8;i++) ids.push((await legacy(db)).rows[0].id);
  await rejectsCode(legacy(db),'ERR_EVERROOT_LEGACY_LIMIT');
  await db.query('update legacy_family_members set replaced_by_vault_id=$1 where id=$2',[vault,ids[0]]);
  await rejectsCode(legacy(db,familyA,vault),'ERR_EVERROOT_LEGACY_LIMIT');
  const other=(await legacy(db,familyB)).rows[0].id;
  await rejectsCode(db.query('update legacy_family_members set family_id=$1 where id=$2',[familyA,other]),'ERR_EVERROOT_LEGACY_LIMIT');
  await setBytes(db,cap);
  await db.query("update legacy_family_members set name='Existing profile' where id=$1",[ids[1]]);
  await rejectsCode(db.query('update legacy_family_members set replaced_by_vault_id=null where id=$1',[ids[0]]),'ERR_EVERROOT_STORAGE_LIMIT');
}));

test('hourly actor cap survives consumed/deleted invites and resets after a rolling hour',()=>run(async db=>{
  for(let i=0;i<20;i++) {
    const row=await invite(db);
    await db.query('delete from family_invites where id=$1',[row.rows[0].id]);
    await ageEvents(db);
  }
  await rejectsCode(invite(db),'ERR_EVERROOT_INVITE_RATE_LIMIT');
  await db.exec("update family_access.invite_rate_events set created_at=clock_timestamp()-interval '61 minutes'");
  await invite(db);
  assert.equal((await db.query('select count(*)::int as n from family_access.invite_rate_events')).rows[0].n,1);
}));

test('family hourly cap cannot be bypassed with different senders',()=>run(async db=>{
  for(let i=0;i<50;i++) {
    const row=await invite(db,{actor:randomUUID()});
    await db.query('delete from family_invites where id=$1',[row.rows[0].id]);
  }
  await rejectsCode(invite(db,{actor:randomUUID()}),'ERR_EVERROOT_INVITE_RATE_LIMIT');
}));

test('pending cap, duplicate recipients and cooldown remain, even with forged timestamps',()=>run(async db=>{
  await invite(db,{email:'Person@Example.com',phone:'+27 (71) 234-5678',created:'2000-01-01T00:00:00Z'});
  await rejectsCode(invite(db,{created:'2100-01-01T00:00:00Z'}),'ERR_EVERROOT_INVITE_COOLDOWN');
  await ageEvents(db);
  await rejectsCode(invite(db,{email:' person@example.com '}),'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT');
  await rejectsCode(invite(db,{phone:'27712345678'}),'ERR_EVERROOT_DUPLICATE_INVITE_RECIPIENT');
  for(let i=1;i<10;i++) { await invite(db); await ageEvents(db); }
  await rejectsCode(invite(db),'ERR_EVERROOT_PENDING_INVITE_LIMIT');
  assert.equal((await db.query('select count(*)::int as n from family_access.invite_rate_events')).rows[0].n,10);
}));

test('monthly totals no longer gate growth; existing invite identity cannot be recycled',()=>run(async db=>{
  await db.query("insert into everroot_invite_usage_periods values($1,date_trunc('month',now())::date,999)",[familyA]);
  const id=(await invite(db)).rows[0].id;
  for(const update of ["created_at=now()-interval '1 day'","invite_code='recycled'","expires_at=now()+interval '3 days'",`family_id='${familyB}'`])
    await assert.rejects(db.query(`update family_invites set ${update} where id=$1`,[id]),e=>e.code==='42501');
  await db.query('update family_invites set used_at=now() where id=$1',[id]);
  await assert.rejects(db.query('update family_invites set used_at=null where id=$1',[id]),e=>e.code==='42501');
}));

test('RLS and private rate ledger cannot be bypassed by an outsider',()=>run(async db=>{
  await db.query("select set_config('test.uid',$1,false)",[ownerB]);
  await db.exec('set role authenticated');
  await assert.rejects(invite(db,{actor:ownerA}),e=>e.code==='42501');
  await assert.rejects(invite(db,{actor:ownerB}),e=>e.code==='42501');
  await assert.rejects(db.exec('delete from family_access.invite_rate_events'),e=>e.code==='42501');
  await assert.rejects(db.query('select everroot_assert_can_add_family_member($1,$2)',[familyA,user]),e=>e.code==='42501');
  await db.exec('reset role');
  await db.query("select set_config('test.uid',$1,false)",[ownerA]);
  await db.exec('set role authenticated');
  await invite(db);
  await db.exec('reset role');
}));
