import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261001215816_ai_processing_consent.sql',import.meta.url),'utf8');
const a = '00000000-0000-4000-8000-000000000001';
const b = '00000000-0000-4000-8000-000000000002';
test('consent defaults off, is isolated per account, revocable and not directly writable', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create schema auth;
      create table auth.users(id uuid primary key);
      insert into auth.users values('${a}'),('${b}');
      create function auth.uid() returns uuid language sql as
        $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
      grant usage on schema auth to authenticated;`);
    await db.exec(migration);
    await db.exec(`set role authenticated; select set_config('test.uid','${a}',false);`);
    const allowed = async () => (await db.query('select has_ai_processing_consent() as allowed')).rows[0].allowed;
    assert.equal(await allowed(),false);
    await db.query('select set_ai_processing_consent(true)');
    assert.equal(await allowed(),true);
    await assert.rejects(db.query('select * from ai_processing_consents'), /permission denied/);
    await assert.rejects(db.query("update ai_processing_consents set allowed=true"), /permission denied/);
    await db.query("select set_config('test.uid',$1,false)",[b]);
    assert.equal(await allowed(),false);
    await db.query("select set_config('test.uid',$1,false)",[a]);
    await db.query('select set_ai_processing_consent(false)');
    assert.equal(await allowed(),false);
    await db.exec('reset role; set role anon;');
    await assert.rejects(db.query('select set_ai_processing_consent(true)'), /permission denied/);
  } finally { await db.close(); }
});
