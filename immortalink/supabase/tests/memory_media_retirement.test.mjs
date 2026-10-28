import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixture,report,act,next,status,move,finish,ids,owner,viewer,family,legacy,vault,memory,sibling,legacyMemory,lease,
  photoPath,audioPath,siblingPath,legacyPath } from './helpers/retirement_fixture.mjs';

test('personal photo/audio move atomically, preserve ownership and sibling, restore never reuses old paths',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');
    assert.equal((await status(db,id)).pending,2);
    await assert.rejects(act(db,id,'restore'),/SAFETY_MEDIA_RETIREMENT_PENDING/);
    const job=await next(db,id);assert.deepEqual(await next(db,id),job);
    const object=(await db.query('select id,owner,owner_id,metadata from storage.objects where name=$1',[job.source])).rows[0];
    await move(db,job);
    const moved=(await db.query('select id,owner,owner_id,metadata from storage.objects where name=$1',[job.destination])).rows[0];
    assert.notEqual(moved.metadata.lastModified,object.metadata.lastModified);
    delete moved.metadata.lastModified;delete object.metadata.lastModified;assert.deepEqual(moved,object);
    assert.equal((await db.query('select count(*)::int n from memory_photos where path=$1',[siblingPath])).rows[0].n,1);
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
    const paths=(await db.query('select path from memory_photos where memory_id=$1 union all select path from memory_voice_notes where memory_id=$1',[memory])).rows;
    assert.equal(paths.length,2);assert.ok(paths.every(r=>r.path!==photoPath&&r.path!==audioPath));
    assert.ok(paths.some(r=>r.path.endsWith('.png')));assert.ok(paths.some(r=>r.path.endsWith('.m4a')));
    await act(db,id,'restore');assert.equal((await status(db,id)).state,'visible');
    for(const row of paths)assert.equal((await db.query('select count(*)::int n from storage.objects where name=$1',[row.path])).rows[0].n,1);
    await act(db,id,'hide');await finish(db,id);assert.equal((await status(db,id)).completed,2);
    assert.equal((await db.query('select count(*)::int n from content_safety.media_retirement_files')).rows[0].n,4);
  }finally{await db.close();}
});
test('repeat hide and another report reuse the pending batch; resolved cases remain in queue',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const first=await next(db,id);
    await act(db,id,'hide');assert.deepEqual(await next(db,id),first);
    const other=await report(db);await act(db,other,'hide');assert.deepEqual(await next(db,other),first);
    await act(db,id,'dismiss');
    const queue=(await db.query('select content_review_queue() data')).rows[0].data;
    assert.ok(queue.some(r=>r.id===id&&r.media_state==='pending'));
    await finish(db,other);await act(db,other,'restore');
    assert.equal((await status(db,id)).hidden,false);
  }finally{await db.close();}
});
test('forged jobs, metadata changes, old-address upload and reattachment fail closed',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const job=await next(db,id);
    await assert.rejects(db.query('update storage.objects set name=$1,metadata=$2 where name=$3',
      [job.destination,{size:900},job.source]),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await assert.rejects(db.query('update storage.objects set name=$1 where name=$2',[`${job.destination}-forged`,job.source]),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await db.exec("select set_config('test.role','authenticated',false)");
    await assert.rejects(move(db,job),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await db.exec("select set_config('test.role','service_role',false)");
    await finish(db,id);await act(db,id,'restore');
    await assert.rejects(db.query('insert into storage.objects(bucket_id,name) values($1,$2)',[job.bucket,job.source]),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await assert.rejects(db.query('insert into storage.objects(bucket_id,name) values($1,$2)',['memory_photos',job.source]),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await assert.rejects(db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,job.source]),/SAFETY_MEDIA_ADDRESS_RETIRED/);
  }finally{await db.close();}
});
test('malformed direct references remain visibly blocked rather than silently omitted',async()=>{
  const db=await fixture();try{
    await db.query('update memory_photos set vault_id=$1 where path=$2',[ids[19],photoPath]);
    const id=await report(db);await act(db,id,'hide');assert.equal(await next(db,id),null);
    assert.equal((await status(db,id)).issue,'attachment_unavailable');
    await assert.rejects(act(db,id,'restore'),/SAFETY_MEDIA_RETIREMENT_PENDING/);
  }finally{await db.close();}
});
test('restore requires a fresh case revision after a move',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');
    const before=(await db.query("select preview_content_report($1,'QA') data",[id])).rows[0].data;
    await finish(db,id);
    await assert.rejects(db.query("select review_content_report_checked($1,'restore','QA','QA',$2)",[id,before.revision]),/SAFETY_CASE_CHANGED/);
    await act(db,id,'restore');
  }finally{await db.close();}
});
test('a queued operation cannot follow a target into a different family',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const job=await next(db,id);
    await db.query('insert into family_groups(id,created_by,name) values($1,$2,\'Other\')',[ids[19],owner]);
    await db.query('update vaults set family_id=$1 where id=$2',[ids[19],vault]);
    await db.query('delete from family_members where family_id=$1 and user_id=$2',[family,owner]);
    await assert.rejects(move(db,job),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    assert.equal(await next(db,id),null);assert.equal((await status(db,id)).issue,'target_changed');
  }finally{await db.close();}
});
test('a reference failure rolls back the metadata rename and leaves the job retryable',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const job=await next(db,id);
    await db.exec(`create function fail_ref() returns trigger language plpgsql as $$begin raise exception 'QA_FAILURE';end;$$;
      create trigger zz_fail before update on memory_photos for each row execute function fail_ref();
      create trigger zz_fail before update on memory_voice_notes for each row execute function fail_ref();`);
    await assert.rejects(move(db,job),/QA_FAILURE/);
    assert.deepEqual(await next(db,id),job);
    assert.equal((await db.query('select count(*)::int n from storage.objects where name=$1',[job.source])).rows[0].n,1);
    await db.exec('drop trigger zz_fail on memory_photos;drop trigger zz_fail on memory_voice_notes');
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
  }finally{await db.close();}
});
test('new hidden attachments are denied and unexpected shared paths are held without moving a sibling',async()=>{
  const db=await fixture();try{
    await db.query('insert into vault_about_photos(vault_id,path) values($1,$2)',[vault,photoPath]);
    const id=await report(db);await act(db,id,'hide');assert.equal(await next(db,id),null);
    assert.equal((await status(db,id)).issue,'shared_reference');
    await assert.rejects(db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)',[vault,memory,siblingPath]),/SAFETY_MEMORY_HIDDEN/);
    assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,5);
    await db.query('delete from vault_about_photos where path=$1',[photoPath]);
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
  }finally{await db.close();}
});
test('ambiguous bucket references are blocked, not guessed',async()=>{
  const db=await fixture();try{
    await db.query("insert into storage.objects(bucket_id,name,owner,owner_id) values('memory_photos',$1,$2::uuid,$2)",[photoPath,owner]);
    const id=await report(db);await act(db,id,'hide');assert.equal(await next(db,id),null);
    assert.equal((await status(db,id)).issue,'attachment_unavailable');
  }finally{await db.close();}
});
test('same-byte approved maintenance works when full/expired but arbitrary uploads do not',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');
    await db.exec("select set_config('test.full','true',false)");
    await assert.rejects(db.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3)',
      ['vault_photos',`${siblingPath}-new`,owner]),/ERR_EVERROOT_STORAGE_LIMIT/);
    await move(db,await next(db,id));
    await db.exec("select set_config('test.expired','true',false)");
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
    await assert.rejects(db.query('update storage.objects set name=$1 where name=$2',[`${siblingPath}-rename`,siblingPath]),/FAMILY_EXPIRED/);
  }finally{await db.close();}
});
test('legacy photo/audio retains its scope and survives contributor deletion after retirement',async()=>{
  const db=await fixture();try{
    const id=await report(db,'legacy_memory');await act(db,id,'hide');await finish(db,id);
    await db.query('select claim_account_deletion($1,$2)',[owner,lease]);
    await db.exec(`insert into storage.objects(bucket_id,name,metadata)
      select bucket_id,target_path,jsonb_build_object('size',size_bytes) from account_deletion_files where target_path is not null;`);
    await db.query('select finalize_account_deletion_data($1,$2)',[owner,lease]);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    await db.query('delete from account_deletion_jobs where user_id=$1',[owner]);
    await finish(db,id);await act(db,id,'restore');
    const paths=(await db.query('select path from legacy_memory_photos union all select path from legacy_memory_voice_notes')).rows;
    assert.equal(paths.length,2);assert.ok(paths.every(r=>r.path.includes('/retained/')));
    for(const {path} of paths){
      const o=(await db.query('select * from storage.objects where name=$1',[path])).rows[0];
      assert.equal(o.owner,null);assert.equal(o.owner_id,null);
      assert.equal((await db.query('select media_object_matches_scope($1,$2,$3,null,$4,$5) ok',[o.bucket_id,path,family,legacy,legacyMemory])).rows[0].ok,true);
    }
    assert.equal((await db.query('select user_id from family_members')).rows[0].user_id,viewer);
  }finally{await db.close();}
});
test('deletion wins before a move: pending jobs never block deletion or lose shared bytes',async()=>{
  const db=await fixture();try{
    const id=await report(db,'legacy_memory');await act(db,id,'hide');const stale=await next(db,id);
    await db.query('select claim_account_deletion($1,$2)',[owner,lease]);
    assert.equal(await next(db,id),null);assert.equal((await status(db,id)).issue,'deletion_in_progress');
    await assert.rejects(move(db,stale),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    await db.exec(`insert into storage.objects(bucket_id,name,metadata)
      select bucket_id,target_path,jsonb_build_object('size',size_bytes) from account_deletion_files where target_path is not null;`);
    await db.query('select finalize_account_deletion_data($1,$2)',[owner,lease]);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    await db.query('delete from account_deletion_jobs where user_id=$1',[owner]);
    await finish(db,id);await act(db,id,'restore');
    assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,2);
    assert.equal((await db.query('select count(*)::int n from content_safety.media_retirement_files where state=\'deleted\'')).rows[0].n,2);
  }finally{await db.close();}
});
test('last-member deletion includes rotated legacy files and pending personal jobs can reconcile deleted objects',async()=>{
  const db=await fixture();try{
    const id=await report(db),legacyReport=await report(db,'legacy_memory');
    await act(db,id,'hide');await act(db,legacyReport,'hide');await finish(db,legacyReport);
    await db.query('delete from family_members where user_id=$1',[viewer]);
    await db.query('select claim_account_deletion($1,$2)',[owner,lease]);
    await db.exec(`insert into storage.objects(bucket_id,name,metadata)
      select bucket_id,target_path,jsonb_build_object('size',size_bytes) from account_deletion_files where target_path is not null;`);
    await db.query('select finalize_account_deletion_data($1,$2)',[owner,lease]);
    await db.exec('delete from storage.objects o using account_deletion_files f where o.bucket_id=f.bucket_id and o.name=f.source_path');
    await db.query('delete from account_deletion_jobs where user_id=$1',[owner]);
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
    assert.equal((await db.query('select count(*)::int n from storage.objects')).rows[0].n,0);
  }finally{await db.close();}
});
test('clients cannot access jobs, service cannot bypass private originals, and non-memory hides do not relocate archives',async()=>{
  const db=await fixture();try{
    for(const role of ['anon','authenticated']) {
      for(const fn of ['next_content_media_retirement(uuid)','content_report_media_status(uuid)','content_review_queue()','claim_account_deletion(uuid,uuid)'])
        assert.equal((await db.query('select has_function_privilege($1,$2,\'execute\') ok',[role,fn])).rows[0].ok,false);
      assert.equal((await db.query("select has_table_privilege($1,'content_safety.media_retirement_files','select') ok",[role])).rows[0].ok,false);
    }
    assert.equal((await db.query("select has_function_privilege('service_role','content_safety.review_content_report(uuid,text,text,text)','execute') ok")).rows[0].ok,false);
    const id=await report(db);await db.query("update content_reports set target_kind='vault',target_id=$1 where id=$2",[vault,id]);
    await act(db,id,'hide');assert.equal(await next(db,id),null);assert.equal((await status(db,id)).state,'not_applicable');
    assert.equal((await db.query('select count(*)::int n from content_safety.media_retirement_files')).rows[0].n,0);
  }finally{await db.close();}
});
test('ordinary owner saves still return the memory and attach a new photo after the migration',async()=>{
  const db=await fixture();try{
    await db.query("select set_config('test.uid',$1,false)",[owner]);
    await db.exec(`select set_config('test.role','authenticated',false);
      grant select,insert on memories,memory_photos,vaults,family_members to authenticated;
      alter table memories enable row level security;
      create policy qa_owner_read on memories for select to authenticated using(
        exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));
      create policy qa_owner_insert on memories for insert to authenticated with check(
        exists(select 1 from vaults v where v.id=vault_id and v.owner_id=auth.uid()));
      set role authenticated;`);
    const fresh=ids[19],path=`${owner}/${vault}/memories/${fresh}/new.png`;
    assert.equal((await db.query('insert into memories(id,vault_id,body) values($1,$2,\'New QA\') returning id',[fresh,vault])).rows[0].id,fresh);
    await db.query("insert into storage.objects(bucket_id,name,owner,owner_id) values('vault_photos',$1,$2::uuid,$2)",[path,owner]);
    assert.equal((await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3) returning path',[vault,fresh,path])).rows[0].path,path);
  }finally{await db.close();}
});
test('Storage permission-probe rollback changes neither references nor the durable job',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const job=await next(db,id);
    await db.exec('begin;savepoint permission_probe');await move(db,job);
    await db.exec('rollback to permission_probe;release permission_probe;commit');
    assert.deepEqual(await next(db,id),job);
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
  }finally{await db.close();}
});
test('public or versioned buckets fail closed even when changed after job preparation',async()=>{
  const db=await fixture();try{
    const id=await report(db);await act(db,id,'hide');const job=await next(db,id);
    await db.query("update storage.buckets set versioning_status='ENABLED' where id=$1",[job.bucket]);
    await assert.rejects(move(db,job),/SAFETY_MEDIA_ADDRESS_RESERVED/);
    assert.equal(await next(db,id),null);assert.equal((await status(db,id)).issue,'unsupported_bucket');
    await db.query("update storage.buckets set versioning_status='DISABLED',public=true where id=$1",[job.bucket]);
    assert.equal(await next(db,id),null);
    await db.query('update storage.buckets set public=false where id=$1',[job.bucket]);
    await finish(db,id);assert.equal((await status(db,id)).state,'retired');
  }finally{await db.close();}
});
