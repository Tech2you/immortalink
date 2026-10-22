import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261007213340_media_reference_authorization.sql', import.meta.url), 'utf8');
const avatarMigration = await readFile(new URL('../migrations/20261007214130_scope_avatar_reads.sql', import.meta.url), 'utf8');
const ids = Array.from({length: 12}, (_, n) => `00000000-0000-4000-8000-${String(n+1).padStart(12,'0')}`);
const [alice,bob,outsider,family,otherFamily,legacy,otherLegacy,vault,otherVault,memory,otherMemory,legacyMemory] = ids;
const shared = `${alice}/${family}/legacy/${legacy}/gallery/photo.jpg`;
const privatePath = `${outsider}/${otherVault}/private.jpg`;
async function fixture() {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth; create schema storage;
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function auth.jwt() returns jsonb language sql as $$select jsonb_build_object('role',coalesce(current_setting('test.role',true),'authenticated'))$$;
    create table family_members(family_id uuid,user_id uuid);
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid);
    create table memories(id uuid primary key,vault_id uuid);
    create table legacy_family_members(id uuid primary key,family_id uuid,avatar_path text);
    create table legacy_memories(id uuid primary key,legacy_member_id uuid,family_id uuid);
    create table storage.objects(bucket_id text,name text,owner uuid,owner_id text);
    create function can_read_vault_media(v uuid) returns boolean language sql security definer as $$
      select exists(select 1 from vaults where id=v and (owner_id=auth.uid() or exists(
        select 1 from family_members fm where fm.family_id=vaults.family_id and fm.user_id=auth.uid())))$$;
    insert into family_members values('${family}','${alice}'),('${family}','${bob}'),('${otherFamily}','${outsider}');
    insert into vaults values('${vault}','${alice}','${family}'),('${otherVault}','${outsider}','${otherFamily}');
    insert into memories values('${memory}','${vault}'),('${otherMemory}','${otherVault}');
    insert into legacy_family_members values('${legacy}','${family}',null),('${otherLegacy}','${otherFamily}',null);
    insert into legacy_memories values('${legacyMemory}','${legacy}','${family}');
    insert into storage.objects values('vault_photos','${shared}','${alice}','${alice}'),
      ('vault_photos','${privatePath}','${outsider}','${outsider}');`);
  for (const table of ['legacy_member_photos','legacy_memory_photos','legacy_memory_voice_notes','legacy_vault_about_photos','legacy_vault_core_voice_note']) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid(),family_id uuid,legacy_member_id uuid,legacy_memory_id uuid,path text);`);
  }
  for (const table of ['memory_photos','memory_voice_notes','vault_highlight_photos','vault_about_photos','vault_core_voice_note','voice_notes','vault_media','vault_voice_notes']) {
    await db.exec(`create table ${table}(id uuid default gen_random_uuid(),vault_id uuid,memory_id uuid,path text,storage_path text);`);
  }
  await db.exec(`create view legacy_media_references as select 'legacy_member_photos'::text relation_name,p.id row_id,l.family_id,p.path,
      array['vault_photos','legacy_vault_photos'] buckets from legacy_member_photos p join legacy_family_members l on l.id=p.legacy_member_id;
    grant usage on schema auth,storage to authenticated;
    grant select,insert,update on all tables in schema public to authenticated;
    grant select on storage.objects to authenticated;
    alter table storage.objects enable row level security;`);
  await db.exec(migration);
  await db.exec(`create policy legacy_read on storage.objects for select to authenticated using(can_read_legacy_gallery_object(bucket_id,name));
    create policy shared_read on storage.objects for select to authenticated using(can_read_shared_media_object(bucket_id,name));
    set role authenticated; select set_config('test.uid','${bob}',false);`);
  return db;
}
test('shared contribution is readable but forged foreign/private references are rejected', async () => {
  const db=await fixture(); try {
    await db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,legacy,shared]);
    assert.deepEqual((await db.query('select name from storage.objects')).rows,[{name:shared}]);
    await assert.rejects(db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,legacy,privatePath]),/SCOPE_MISMATCH/);
    await assert.rejects(db.query('update legacy_member_photos set path=$1',[privatePath]),/SCOPE_MISMATCH/);
    await db.query("select set_config('test.uid',$1,false)",[outsider]);
    assert.equal((await db.query('select name from storage.objects where name=$1',[shared])).rows.length,0);
  } finally {await db.close();}
});
test('family/profile/memory parents must agree and cannot be reassigned',async()=>{
  const db=await fixture();try{
    await assert.rejects(db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,otherLegacy,shared]),/FAMILY_MISMATCH/);
    await assert.rejects(db.query('insert into legacy_memories(legacy_member_id,family_id) values($1,$2)',[otherLegacy,family]),/FAMILY_MISMATCH/);
    await db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,legacy,shared]);
    await assert.rejects(db.query('update legacy_member_photos set family_id=$1',[otherFamily]),/PARENT_IMMUTABLE/);
    await assert.rejects(db.query('insert into legacy_memory_photos(family_id,legacy_member_id,legacy_memory_id,path) values($1,$2,$3,$4)',[family,legacy,otherMemory,shared]),/MEMORY_MISMATCH/);
  }finally{await db.close();}
});
test('personal voice references cannot borrow another vault or memory',async()=>{
  const db=await fixture();try{
    await db.query("select set_config('test.uid',$1,false)",[alice]);
    await assert.rejects(db.query('insert into memory_voice_notes(vault_id,memory_id,path) values($1,$2,$3)',[vault,otherMemory,privatePath]),/MEMORY_MISMATCH/);
    await assert.rejects(db.query('insert into memory_voice_notes(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,privatePath]),/SCOPE_MISMATCH/);
    await assert.rejects(db.query('insert into memory_voice_notes(vault_id,memory_id,path) values($1,$2,$3)',[otherVault,otherMemory,privatePath]),/VAULT_MISMATCH/);
  }finally{await db.close();}
});
test('historical forged rows cannot expand storage visibility',async()=>{
  const db=await fixture();try{
    await db.exec("reset role; select set_config('test.role','service_role',false)");
    await db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,legacy,privatePath]);
    await db.query('insert into vault_highlight_photos(vault_id,path) values($1,$2)',[vault,privatePath]);
    await db.exec("set role authenticated; select set_config('test.role','authenticated',false)");
    assert.equal((await db.query('select * from storage.objects')).rows.length,0);
    await assert.rejects(db.query("select media_object_matches_scope('vault_photos',$1,$2,null,$3,null)",[privatePath,family,legacy]),/permission denied/);
  }finally{await db.close();}
});
test('retained shared copies stay readable after contributor deletion; client uploads cannot impersonate them',async()=>{
  const db=await fixture();try{
    const retained=`${alice}/${family}/retained/object`;
    await db.exec('reset role');
    await db.query("insert into storage.objects values('vault_photos',$1,null,null)",[retained]);
    await db.query('delete from family_members where user_id=$1',[alice]);
    await db.exec('set role authenticated');
    await db.query('insert into legacy_member_photos(family_id,legacy_member_id,path) values($1,$2,$3)',[family,legacy,retained]);
    assert.equal((await db.query('select * from storage.objects where name=$1',[retained])).rows.length,1);
    await db.exec('reset role');
    await db.query('update storage.objects set owner_id=$1 where name=$2',[bob,retained]);
    await db.exec('set role authenticated');
    assert.equal((await db.query('select * from storage.objects where name=$1',[retained])).rows.length,0);
  }finally{await db.close();}
});
test('avatars remain readable to their owner and family, not unrelated or former members',async()=>{
  const db=await fixture();try{
    const avatar=`${alice}/${vault}/avatar.png`;
    await db.exec(`reset role;
      create policy avatars_read_auth on storage.objects for select to authenticated using(bucket_id='avatars');
      create policy avatar_owner on storage.objects for select to authenticated using(bucket_id='avatars' and split_part(name,'/',1)=auth.uid()::text);
      create policy avatar_family on storage.objects for select to authenticated using(bucket_id='avatars' and can_read_vault_media(split_part(name,'/',2)::uuid));`);
    await db.query("insert into storage.objects values('avatars',$1,$2::uuid,$2::text)",[avatar,alice]);
    await db.exec(avatarMigration);
    for (const [user,expected] of [[alice,1],[bob,1],[outsider,0]]) {
      await db.exec('set role authenticated');
      await db.query("select set_config('test.uid',$1,false)",[user]);
      assert.equal((await db.query('select * from storage.objects where name=$1',[avatar])).rows.length,expected);
    }
    await db.exec('reset role');
    await db.query('delete from family_members where user_id=$1',[bob]);
    await db.exec('set role authenticated');
    await db.query("select set_config('test.uid',$1,false)",[bob]);
    assert.equal((await db.query('select * from storage.objects where name=$1',[avatar])).rows.length,0);
  }finally{await db.close();}
});
