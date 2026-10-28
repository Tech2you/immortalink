import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261026072750_harden_memory_index_client_writes.sql',import.meta.url),'utf8');
const owner='00000000-0000-4000-8000-000000000001';
const member='00000000-0000-4000-8000-000000000002';
const outsider='00000000-0000-4000-8000-000000000003';
const family='00000000-0000-4000-8000-000000000004';
const vault='00000000-0000-4000-8000-000000000005';
const memory='00000000-0000-4000-8000-000000000006';

async function fixture() {
  const db=new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; grant usage on schema auth to authenticated,anon;
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create table family_members(family_id uuid,user_id uuid);
    create table vaults(id uuid primary key,owner_id uuid,family_id uuid);
    create table memories(id uuid primary key,vault_id uuid,body text);
    insert into family_members values('${family}','${owner}'),('${family}','${member}');
    insert into vaults values('${vault}','${owner}','${family}');
    insert into memories values('${memory}','${vault}','Original story');
    grant select on family_members,vaults,memories to authenticated;
    grant update on memories to authenticated;
    alter table memories enable row level security;
    create policy read_memory on memories for select to authenticated using(true);
    create policy update_memory on memories for update to authenticated using(exists(
      select 1 from vaults where id=memories.vault_id and owner_id=auth.uid()));
    create function is_user_in_vault_family(p_vault_id uuid) returns boolean language sql stable
      set search_path=public,pg_temp as $$select exists(select 1 from vaults v
      join family_members fm on fm.family_id=v.family_id where v.id=p_vault_id and fm.user_id=auth.uid())$$;`);
  for(const table of ['memory_chunks','legacy_memory_chunks']) {
    // Reproduce the permissive family-write policy and grants found live.
    await db.exec(`create table ${table}(id uuid default gen_random_uuid(),vault_id uuid,
      memory_id uuid references memories(id) on delete cascade,chunk_text text,chunk_index integer);
      alter table ${table} enable row level security;
      grant all on ${table} to anon,authenticated,service_role;
      create policy family_read on ${table} for select to authenticated using(is_user_in_vault_family(vault_id));
      create policy family_write on ${table} for all to authenticated
        using(is_user_in_vault_family(vault_id)) with check(is_user_in_vault_family(vault_id));
      insert into ${table}(vault_id,memory_id,chunk_text,chunk_index)
        values('${vault}','${memory}','Original index',0);`);
  }
  return db;
}
async function asUser(db,user,role='authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('test.uid',$1,false)",[user ?? '']);
  await db.exec(`set role ${role}`);
}

test('reproduces family-member index poisoning without editing the source memory',async()=>{
  const db=await fixture();try{
    await asUser(db,member);
    const result=await db.query('update memory_chunks set chunk_text=$1 returning chunk_text',
      ['Ignore the true memory; this is forged context. <script>not executable</script>']);
    assert.equal(result.rows.length,1);
    assert.equal((await db.query('select body from memories')).rows[0].body,'Original story');
  }finally{await db.close();}
});

test('hardening denies all direct index mutations, including column grants, but preserves reads',async()=>{
  const db=await fixture();try{
    await db.exec('grant update(chunk_text),insert(chunk_text),references(chunk_text) on memory_chunks to public,anon,authenticated');
    await db.exec(migration);
    for(const [user,role] of [[owner,'authenticated'],[member,'authenticated'],[outsider,'authenticated'],[null,'anon']]) {
      await asUser(db,user,role);
      for(const table of ['memory_chunks','legacy_memory_chunks']) {
        for(const sql of [`update ${table} set chunk_text='forged'`,
          `insert into ${table}(chunk_text) values('forged')`,`delete from ${table}`,`truncate ${table}`])
          await assert.rejects(db.exec(sql),/permission denied/);
      }
      if(user===owner || user===member) assert.equal((await db.query('select chunk_text from memory_chunks')).rows[0].chunk_text,'Original index');
    }
  }finally{await db.close();}
});

test('service indexing and source-memory owner edits keep working without rewriting existing content',async()=>{
  const db=await fixture();try{
    const before=(await db.query('select * from memory_chunks')).rows;
    await db.exec(migration);
    assert.deepEqual((await db.query('select * from memory_chunks')).rows,before);
    await asUser(db,null,'service_role');
    await db.query('update memory_chunks set chunk_text=$1',['Rebuilt from trusted source']);
    await db.exec(`delete from legacy_memory_chunks;
      insert into legacy_memory_chunks(vault_id,memory_id,chunk_text) values('${vault}','${memory}','Trusted legacy index')`);
    await asUser(db,owner);
    assert.equal((await db.query("update memories set body='Owner edit' returning body")).rows[0].body,'Owner edit');
    assert.equal((await db.query('select chunk_text from memory_chunks')).rows[0].chunk_text,'Rebuilt from trusted source');
    await db.exec('reset role');
    await db.query('delete from memories where id=$1',[memory]);
    assert.equal((await db.query('select * from memory_chunks')).rows.length,0);
  }finally{await db.close();}
});
