import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const sql=await readFile(new URL('../migrations/20260927230146_usage_burst_protection.sql',import.meta.url),'utf8');
test('burst guard meters AI units, separates members, resets and guards transcription',async()=>{
  const db=new PGlite();
  const a='00000000-0000-4000-8000-000000000001',b='00000000-0000-4000-8000-000000000002';
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role;
      create schema auth; create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
      create function everroot_family_plan(uuid) returns text language sql as $$select 'free'::text$$;
      insert into auth.users values('${a}'),('${b}'); select set_config('test.uid','${a}',false);`);
    for(const name of ['everroot_consume_ai_usage','everroot_consume_transcription_usage']) {
      await db.exec(`create function ${name}(p_family_id uuid,p_vault_id uuid,p_units integer) returns text language plpgsql as $$
        declare v_family_id uuid := p_family_id; v_plan text;
        begin v_plan := public.everroot_family_plan(v_family_id); return v_plan; end;$$;`);
    }
    await db.exec(sql);
    await db.query('select everroot_consume_ai_usage(null,null,6)');
    await assert.rejects(db.query('select everroot_consume_ai_usage(null,null,1)'),/Please wait/);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    await db.query('select everroot_consume_ai_usage(null,null,1)');
    await assert.rejects(db.query('select everroot_consume_ai_usage(null,null,100)'),/Please wait/);
    for(let i=0;i<3;i++) await db.query('select everroot_consume_transcription_usage(null,null,120)');
    await assert.rejects(db.query('select everroot_consume_transcription_usage(null,null,120)'),/Please wait/);
    await db.exec("update everroot_usage_bursts set window_started_at=now()-interval '61 seconds'");
    await db.query('select everroot_consume_transcription_usage(null,null,120)');
    assert.equal((await db.query("select has_function_privilege('authenticated','everroot_assert_usage_burst(text,integer)','execute') as allowed")).rows[0].allowed,false);
  } finally {await db.close();}
});
