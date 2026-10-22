import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const read = (name) => readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');
const baseline = await read('20260809100000_everroot_entitlements_and_quotas.sql');
const transcription = await read('20260823224804_everroot_ai_transcription_cost_controls.sql');
const plans = await read('20260826194454_everroot_three_tier_billing_model.sql');
const migration = await read('20260928212929_expired_family_read_only.sql');
function definition(source,name) {
  const start = source.indexOf(`create or replace function public.${name}(`);
  assert.ok(start>=0,name);
  return source.slice(start,source.indexOf('$$;',start)+3);
}
const f='00000000-0000-4000-8000-000000000001';

test('expired over-limit families retain reads, block additions and recover after renewal/reduction',async()=>{
  const db=new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role;
      create schema auth; create schema storage;
      create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
      create table family_entitlements(family_id uuid,plan text,status text,current_period_end timestamptz);
      create table family_members(family_id uuid);
      create table legacy_family_members(family_id uuid,replaced_by_vault_id uuid);
      create table memories(id uuid,vault_id uuid,body text);
      create table legacy_memories(id uuid,family_id uuid,body text);
      create function everroot_storage_bytes_used(uuid,uuid) returns bigint language sql as
        $$select coalesce(nullif(current_setting('test.bytes',true),''),'0')::bigint$$;
      create function everroot_memory_count(uuid,uuid) returns integer language sql as $$select 0$$;
      create function everroot_photo_count(uuid,uuid) returns integer language sql as $$select 0$$;
      create function everroot_voice_note_count(uuid,uuid) returns integer language sql as $$select 0$$;
      create function everroot_family_for_vault(uuid) returns uuid language sql as $$select $1$$;
    `);
    for(const name of ['everroot_family_plan','everroot_limits']) await db.exec(definition(plans,name));
    for(const name of ['everroot_limit_int','everroot_limit_bigint','everroot_quota_error',
      'everroot_assert_memory_capacity','everroot_assert_legacy_memory_capacity',
      'everroot_assert_legacy_person_capacity','everroot_assert_photo_capacity',
      'everroot_assert_voice_note_capacity','everroot_assert_storage_object_capacity',
      'everroot_consume_ai_usage']) await db.exec(definition(baseline,name));
    await db.exec(definition(transcription,'everroot_consume_transcription_usage'));
    await db.exec(migration);
    await db.exec(`create trigger capacity before insert on memories for each row execute function everroot_assert_memory_capacity();
      create trigger capacity before insert on legacy_memories for each row execute function everroot_assert_legacy_memory_capacity();
      insert into family_entitlements values ('${f}','everroot_family','active',now()+interval '1 day');
      select set_config('test.bytes','600000000',false);`);
    const frozen=async()=> (await db.query('select everroot_family_is_read_only($1) as frozen',[f])).rows[0].frozen;
    assert.equal(await frozen(),false,'paid access remains until expiry');
    await db.query('insert into memories values($1,$1,$2)',[f,'Existing memory']);
    await db.exec("update family_entitlements set current_period_end=now()-interval '1 second'");
    assert.equal(await frozen(),true);
    assert.equal((await db.query('select body from memories')).rows[0].body,'Existing memory');
    await assert.rejects(db.query('insert into memories values($1,$1,$2)',[f,'Blocked']),/free plan limits/);
    await assert.rejects(db.query('insert into legacy_memories values($1,$1,$2)',[f,'Blocked']),/free plan limits/);
    await db.exec('delete from memories');
    assert.equal((await db.query('select count(*) as n from memories')).rows[0].n,0);
    await db.exec("select set_config('test.bytes','0',false)");
    assert.equal(await frozen(),false,'reducing usage unfreezes without a paid plan');
    await db.exec("select set_config('test.bytes','600000000',false); update family_entitlements set current_period_end=now()+interval '1 day'");
    assert.equal(await frozen(),false,'renewal restores writes');
    const rows=(await db.query("select has_function_privilege('anon','everroot_family_is_read_only(uuid)','execute') as allowed")).rows;
    assert.equal(rows[0].allowed,false);
  } finally {await db.close();}
});
