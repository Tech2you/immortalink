import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261001215851_legacy_gallery_read_access.sql',import.meta.url),'utf8');
const followup = await readFile(new URL('../migrations/20261001221334_complete_legacy_gallery_reads.sql',import.meta.url),'utf8');
test('only retained family members can read referenced legacy gallery objects', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create schema auth; create schema storage;
      create function auth.uid() returns text language sql as $$select current_setting('test.uid',true)$$;
      grant usage on schema auth,storage to authenticated;
      create table family_members(family_id text,user_id text);
      create table legacy_family_members(id text,family_id text,avatar_path text);
      create table legacy_member_photos(legacy_member_id text,path text);
      create table legacy_memory_photos(legacy_member_id text,path text);
      create table storage.objects(bucket_id text,name text);
      alter table storage.objects enable row level security;
      grant select on storage.objects to authenticated;
      insert into family_members values('family','member');
      insert into legacy_family_members values('legacy','family','departed/avatar');
      insert into legacy_member_photos values('legacy','departed/gallery');
      insert into legacy_memory_photos values('legacy','departed/memory');
      insert into storage.objects values('vault_photos','departed/gallery'),('vault_photos','departed/memory'),
        ('avatars','departed/avatar'),('vault_photos','departed/avatar'),
        ('vault_photos','departed/private'),('memory_photos','departed/gallery'),('memory_voice','departed/avatar');`);
    await db.exec(migration);
    await db.exec(followup);
    await db.exec("set role authenticated; select set_config('test.uid','outsider',false);");
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await db.query("select set_config('test.uid','member',false)");
    assert.equal((await db.query('select * from storage.objects')).rows.length,4);
    await db.exec("reset role; delete from family_members; set role authenticated;");
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
  } finally { await db.close(); }
});
