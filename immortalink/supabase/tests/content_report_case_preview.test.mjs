import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261018210222_content_report_case_preview.sql',import.meta.url),'utf8');
const referenceMigration = await readFile(new URL('../migrations/20261007213340_media_reference_authorization.sql',import.meta.url),'utf8');
const scopeFunction = referenceMigration.split('create function public.guard_media_reference_scope()')[0];
const safetyMigration = await readFile(new URL('../migrations/20261013104043_family_content_safety.sql',import.meta.url),'utf8');
const actionFunction = safetyMigration.slice(safetyMigration.indexOf('create function public.review_content_report('),safetyMigration.indexOf('revoke all on all functions in schema content_safety'));
const ids = Array.from({length:12},(_,n)=>`00000000-0000-4000-8000-${String(n+1).padStart(12,'0')}`);
const [family,otherFamily,legacy,memory,otherMemory,user,vault,report,photo,audio,otherObject] = ids;
const path=`${user}/${family}/legacy/${legacy}/memories/${memory}/photo.jpg`;
async function fixture(){
  const db=new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema storage; create schema content_safety;
    create table storage.objects(id uuid primary key,bucket_id text,name text,owner uuid,owner_id text,updated_at timestamptz default now(),metadata jsonb default '{}');
    create table vaults(id uuid primary key,family_id uuid,owner_id uuid,name text,display_name text,avatar_path text);
    create table family_groups(id uuid primary key,name text);
    create table family_members(family_id uuid,user_id uuid);
    create table legacy_family_members(id uuid primary key,family_id uuid,name text,display_name text,about_me_text text,avatar_path text);
    create table legacy_memories(id uuid primary key,family_id uuid,legacy_member_id uuid,body text,prompt_text text);
    create table legacy_memory_photos(id uuid primary key,family_id uuid,legacy_member_id uuid,legacy_memory_id uuid,path text);
    create table legacy_memory_voice_notes(id uuid primary key,family_id uuid,legacy_member_id uuid,legacy_memory_id uuid,path text);
    create table content_reports(id uuid primary key,family_id uuid,target_kind text,target_id uuid,reason text,details text,status text,subject_user_id uuid,created_at timestamptz default now(),reviewed_at timestamptz);
    create table content_safety.restrictions(target_kind text,target_id uuid,report_id uuid,primary key(target_kind,target_id));
    create table content_safety.review_actions(report_id uuid,action text,reviewer text,notes text);
    insert into family_groups values('${family}','Family'),('${otherFamily}','Other');
    insert into family_members values('${family}','${user}');
    insert into vaults values('${vault}','${family}','${user}','Name',null,null);
    insert into legacy_family_members values('${legacy}','${family}','Grandma',null,'Profile only',null);
    insert into legacy_memories values('${memory}','${family}','${legacy}','Reported story','Prompt'),('${otherMemory}','${family}','${legacy}','PRIVATE OTHER MEMORY',null);
    insert into content_reports(id,family_id,target_kind,target_id,reason,details,status,subject_user_id) values('${report}','${family}','legacy_memory','${memory}','privacy','Please check','open','${user}');
    insert into storage.objects(id,bucket_id,name,owner,owner_id) values('${photo}','vault_photos','${path}','${user}','${user}'),
      ('${audio}','memory_voice','${path}.m4a','${user}','${user}'),
      ('${otherObject}','vault_photos','${user}/${otherFamily}/legacy/${legacy}/memories/${memory}/other.jpg','${user}','${user}');
    insert into legacy_memory_photos values('${photo}','${family}','${legacy}','${memory}','${path}');
    insert into legacy_memory_voice_notes values('${audio}','${family}','${legacy}','${memory}','${path}.m4a');`);
  await db.exec(scopeFunction+actionFunction+migration);
  return db;
}
async function open(db,id=report,reviewer='Ross'){
  return (await db.query('select public.preview_content_report($1,$2) result',[id,reviewer])).rows[0].result;
}
async function act(db,version,action='hide',reviewer='Ross'){
  return db.query('select public.review_content_report_checked($1,$2,$3,$4,$5)',[report,action,reviewer,'Reviewed exact case',version]);
}
test('preview exposes only the reported memory and direct scoped attachments; access audit has no content',async()=>{
  const db=await fixture();try{
    const data=await open(db);assert.equal(data.available,true);assert.equal(data.fields.Memory,'Reported story');
    assert.equal(data.media.length,2);assert.ok(!JSON.stringify(data).includes('PRIVATE OTHER MEMORY'));
    const logs=(await db.query('select * from content_safety.preview_access')).rows;
    assert.equal(logs.length,1);assert.equal(logs[0].reviewer,'Ross');assert.ok(!JSON.stringify(logs).includes('Reported story'));
  }finally{await db.close();}
});
test('ordinary app users and anonymous clients cannot access previews, audit rows or checked actions',async()=>{
  const db=await fixture();try{
    for(const role of ['anon','authenticated']){
      await db.exec(`set role ${role}`);
      await assert.rejects(open(db),/permission denied/);
      await assert.rejects(act(db,'x'),/permission denied/);
      await assert.rejects(db.query('select * from content_safety.preview_access'),/permission denied/);
      await db.exec('reset role');
    }
    await db.exec('set role service_role');assert.equal((await open(db)).available,true);
  }finally{await db.close();}
});
test('forged cross-family references and unrelated media ids cannot be previewed',async()=>{
  const db=await fixture();try{
    await db.query('insert into legacy_memory_photos values($1,$2,$3,$4,$5)',[ids[11],family,legacy,memory,`${user}/${otherFamily}/legacy/${legacy}/memories/${memory}/other.jpg`]);
    const data=await open(db);assert.equal(data.media.length,2);
    await assert.rejects(db.query('select preview_content_report($1,$2,$3,$4)',[report,'Ross',otherObject,data.revision]),/SAFETY_MEDIA_UNAVAILABLE/);
    assert.equal((await db.query('select count(*)::int n from content_safety.preview_access')).rows[0].n,1);
    await db.query('update legacy_memories set family_id=$1 where id=$2',[otherFamily,memory]);
    const missing=await open(db);assert.equal(missing.available,false);assert.equal(missing.media.length,0);
  }finally{await db.close();}
});
test('profile and member reports never expand into the archive; deleted family fails closed',async()=>{
  const db=await fixture();try{
    for(const [kind,id] of [['legacy_profile',legacy],['vault',vault],['member',user],['family',family]]){
      await db.query('update content_reports set target_kind=$1,target_id=$2',[kind,id]);
      const data=await open(db);assert.equal(data.available,true);assert.equal(data.media.length,0);
      assert.ok(!JSON.stringify(data).includes('Reported story'));assert.ok(!JSON.stringify(data).includes('PRIVATE OTHER MEMORY'));
    }
    await db.exec('update content_reports set family_id=null');assert.equal((await open(db)).available,false);
  }finally{await db.close();}
});
test('edits, replaced media and case decisions invalidate old previews',async()=>{
  const db=await fixture();try{
    let data=await open(db);
    await db.exec("update legacy_memories set body='Changed' where body='Reported story'");
    await assert.rejects(act(db,data.revision),/SAFETY_CASE_CHANGED/);
    data=await open(db);await db.exec("update storage.objects set updated_at=now()+interval '1 minute'");
    await assert.rejects(db.query('select preview_content_report($1,$2,$3,$4)',[report,'Ross',photo,data.revision]),/SAFETY_CASE_CHANGED/);
    data=await open(db);await act(db,data.revision);await assert.rejects(act(db,data.revision),/SAFETY_CASE_CHANGED/);
    assert.equal((await db.query('select count(*)::int n from content_safety.review_actions')).rows[0].n,1);
  }finally{await db.close();}
});
test('decisions require a recent preview by the same operator and preserve reversible actions',async()=>{
  const db=await fixture();try{
    let data=await open(db);await assert.rejects(act(db,data.revision,'hide','Someone else'),/SAFETY_PREVIEW_REQUIRED/);
    await db.exec("update content_safety.preview_access set created_at=now()-interval '31 minutes'");
    await assert.rejects(act(db,data.revision),/SAFETY_PREVIEW_REQUIRED/);
    data=await open(db);await act(db,data.revision);assert.equal((await db.query('select * from content_safety.restrictions')).rows.length,1);
    data=await open(db);await act(db,data.revision,'restore');assert.equal((await db.query('select * from content_safety.restrictions')).rows.length,0);
    assert.equal((await db.query('select * from legacy_memories')).rows.length,2);
  }finally{await db.close();}
});
test('retained legacy media is reviewable only through its direct case reference',async()=>{
  const db=await fixture();try{
    const retained=`${user}/${family}/retained/copy.jpg`;
    await db.query('update storage.objects set name=$1,owner=null,owner_id=null where id=$2',[retained,photo]);
    await db.query('update legacy_memory_photos set path=$1',[retained]);
    const data=await open(db);assert.equal(data.media.length,2);
    assert.equal(data.media.find((item)=>item.id===photo).path,retained);
  }finally{await db.close();}
});
test('missing cases and missing reviewer fail without an access grant',async()=>{
  const db=await fixture();try{
    await assert.rejects(open(db,ids[11]),/SAFETY_REPORT_NOT_FOUND/);
    await assert.rejects(open(db,report,' '),/SAFETY_REVIEW_REQUIRED/);
    assert.equal((await db.query('select * from content_safety.preview_access')).rows.length,0);
  }finally{await db.close();}
});
