import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261007213345_voice_transcription_jobs.sql',import.meta.url),'utf8');
test('transcription claims are unique, privately scoped and globally capped',async()=>{
  const db=new PGlite();try{
    await db.exec(`create role anon;create role authenticated;create role service_role;
      create schema auth;create table auth.users(id uuid primary key);`);
    await db.exec(migration);
    const user='00000000-0000-4000-8000-000000000001';
    const scope='00000000-0000-4000-8000-000000000002';
    await db.query('insert into auth.users values($1)',[user]);
    const claim=(hash,seconds=2)=>db.query('select claim_voice_transcription($1,$2,$3,$4,$5) result',[scope,hash,user,user,seconds]);
    assert.equal((await claim('a'.repeat(64))).rows[0].result.claimed,true);
    assert.equal((await claim('a'.repeat(64))).rows[0].result.claimed,false);
    assert.equal((await db.query('select reserved_seconds from voice_transcription_daily_usage')).rows[0].reserved_seconds,120);
    await db.query('select release_voice_transcription($1,$2,$3)',[scope,'a'.repeat(64),scope]);
    assert.equal((await db.query('select reserved_seconds from voice_transcription_daily_usage')).rows[0].reserved_seconds,120);
    await db.query('select release_voice_transcription($1,$2,$3)',[scope,'a'.repeat(64),user]);
    assert.equal((await db.query('select reserved_seconds from voice_transcription_daily_usage')).rows[0].reserved_seconds,0);
    await claim('a'.repeat(64));
    await assert.rejects(claim('b'.repeat(64),121),/check constraint/);
    await db.exec('update voice_transcription_daily_usage set reserved_seconds=7200');
    await assert.rejects(claim('c'.repeat(64)),/DAILY_CAP/);
    assert.equal((await db.query('select * from voice_transcription_jobs')).rows.length,1);
    for(const role of ['anon','authenticated']){
      assert.equal((await db.query("select has_function_privilege($1,'claim_voice_transcription(uuid,text,uuid,uuid,integer)','execute') ok",[role])).rows[0].ok,false);
      assert.equal((await db.query("select has_table_privilege($1,'voice_transcription_jobs','select') ok",[role])).rows[0].ok,false);
    }
    await db.query('delete from auth.users where id=$1',[user]);
    assert.equal((await db.query('select * from voice_transcription_jobs')).rows.length,0);
  }finally{await db.close();}
});
