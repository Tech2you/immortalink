import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
import {setup} from './helpers/media_backup_fixture.mjs';
const id='00000000-0000-4000-8000-000000000001';
const rpc=async(db,name,args=[])=>(await db.query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) value`,args)).rows[0].value;
async function fixture(fn){const db=new PGlite();try{await setup(db);await fn(db);}finally{await db.close();}}
async function start(db){await db.exec('update media_backup.control set enabled=true');await rpc(db,'dispatch_media_backup');
 const token=(await db.query('select headers from net.requests order by id desc limit 1')).rows[0].headers['x-backup-run-token'];
 assert.equal(await rpc(db,'claim_media_backup_run',[token]),true);return token;}
test('backup installs disabled; source rows untouched; clients cannot invoke or read backup data',()=>fixture(async db=>{
 assert.equal(await rpc(db,'dispatch_media_backup'),null);
 for(const role of ['anon','authenticated']){await db.exec(`set role ${role}`);
 for(const [name,args] of [['dispatch_media_backup',[]],['claim_media_backup_run',['a'.repeat(64)]],['next_media_backup_work',['a'.repeat(64)]],['media_backup_manifest',['a'.repeat(64)]],['finish_media_backup_run',['a'.repeat(64)]],['media_backup_source_current',['a'.repeat(64),'b'.repeat(64)]]])await assert.rejects(rpc(db,name,args),/permission denied/);
 await assert.rejects(db.query('select * from media_backup.copies'),/permission denied/);await db.exec('reset role');}
 assert.equal((await db.query('select count(*) n from storage.objects')).rows[0].n,1);
}));
test('single-use run claims, overlapping runs and expiry fail closed',()=>fixture(async db=>{
 const token=await start(db);assert.equal(await rpc(db,'claim_media_backup_run',[token]),false);
 assert.equal(await rpc(db,'dispatch_media_backup'),null);await assert.rejects(rpc(db,'next_media_backup_work',['b'.repeat(64)]),/BACKUP_UNAUTHORIZED/);
 await db.exec("update media_backup.control set busy_until=now()-interval '1 second'");await assert.rejects(rpc(db,'next_media_backup_work',[token]),/BACKUP_UNAUTHORIZED/);
}));
test('owner backup status requires the same owner MFA gate and never exposes paths',()=>fixture(async db=>{
 await db.exec('set role authenticated');await assert.rejects(rpc(db,'business_media_backup_status'),/BUSINESS_ACCESS_DENIED/);await db.exec('reset role');
 await db.exec('create or replace function heiro_business.require_owner() returns uuid language sql as $$select null::uuid$$');
 const status=await rpc(db,'business_media_backup_status');assert.equal(status.enabled,false);assert.equal(status.pending,1);
 assert.equal(JSON.stringify(status).includes('generated/photo.jpg'),false);
}));
test('a source restored during or after pruning is queued again, never falsely complete',()=>fixture(async db=>{
 const token=await start(db),job=await rpc(db,'next_media_backup_work',[token]);
 await rpc(db,'complete_media_backup_work',[token,job.fingerprint,'a'.repeat(64),'b'.repeat(32)]);
 await db.exec("update storage.objects set archived_at=now()");await rpc(db,'next_media_backup_work',[token]);
 await db.exec("update media_backup.copies set retired_at=now()-interval '31 days',attempt_after=now()");
 assert.equal((await rpc(db,'next_media_backup_work',[token])).kind,'delete');
 await db.exec('update storage.objects set archived_at=null');
 assert.equal(await rpc(db,'complete_media_backup_work',[token,job.fingerprint]),false);
 assert.equal((await rpc(db,'media_backup_manifest',[token])).missing,1);
 assert.equal((await rpc(db,'next_media_backup_work',[token])).kind,'copy');
 await db.exec("update media_backup.copies set state='deleted',deleted_at=now()");
 assert.equal((await rpc(db,'next_media_backup_work',[token])).kind,'copy');
}));
test('copy reserves capacity before transfer; retry waits; acknowledgement is idempotent',()=>fixture(async db=>{
 const token=await start(db),job=await rpc(db,'next_media_backup_work',[token]);assert.equal(job.kind,'copy');assert.equal(job.byte_size,100);
 assert.equal(await rpc(db,'next_media_backup_work',[token]),null);assert.equal((await db.query('select copy_bytes from media_backup.control')).rows[0].copy_bytes,100);
 assert.equal((await rpc(db,'media_backup_manifest',[token])).missing,1);
 assert.equal(await rpc(db,'complete_media_backup_work',[token,job.fingerprint,'a'.repeat(64),'b'.repeat(32)]),true);
 assert.equal(await rpc(db,'complete_media_backup_work',[token,job.fingerprint,'a'.repeat(64),'b'.repeat(32)]),false);
 const manifest=await rpc(db,'media_backup_manifest',[token]);assert.equal(manifest.missing,0);assert.equal(manifest.entries.length,1);
 assert.equal(await rpc(db,'next_media_backup_work',[token]),null);
}));
test('daily download and total retained ceilings include pending versions and preserve source',()=>fixture(async db=>{
 const token=await start(db);await db.exec('update media_backup.control set max_daily_copy_bytes=99');
 assert.equal(await rpc(db,'next_media_backup_work',[token]),null);assert.equal((await db.query('select last_error from media_backup.control')).rows[0].last_error,'DAILY_COPY_LIMIT');
 await db.exec('update media_backup.control set max_daily_copy_bytes=1000,max_retained_bytes=99');
 assert.equal(await rpc(db,'next_media_backup_work',[token]),null);assert.equal((await db.query('select last_error from media_backup.control')).rows[0].last_error,'BACKUP_STORAGE_LIMIT');
 await db.exec('update media_backup.control set max_retained_bytes=31*8388608+16384+100');const job=await rpc(db,'next_media_backup_work',[token]);assert.ok(job);
 await db.exec("update storage.objects set version='v2'");assert.equal(await rpc(db,'next_media_backup_work',[token]),null);
 assert.equal((await db.query('select count(*) n from storage.objects')).rows[0].n,1);
}));
test('edit/delete versions retained for recovery; pruning never deletes source records',()=>fixture(async db=>{
 const token=await start(db),job=await rpc(db,'next_media_backup_work',[token]);
 await rpc(db,'complete_media_backup_work',[token,job.fingerprint,'a'.repeat(64),'b'.repeat(32)]);
 await db.exec("update storage.objects set version='v2'");const next=await rpc(db,'next_media_backup_work',[token]);assert.notEqual(next.fingerprint,job.fingerprint);
 assert.equal((await db.query('select count(*) n from media_backup.copies where retired_at is not null')).rows[0].n,1);
 await db.exec("update media_backup.copies set retired_at=now()-interval '31 days',attempt_after=now() where retired_at is not null");
 const prune=await rpc(db,'next_media_backup_work',[token]);assert.equal(prune.kind,'delete');assert.equal(prune.fingerprint,job.fingerprint);
 await rpc(db,'complete_media_backup_work',[token,job.fingerprint]);assert.equal((await db.query('select count(*) n from storage.objects')).rows[0].n,1);
}));
test('manifest rejects unknown buckets or malformed source metadata; archived versions excluded',()=>fixture(async db=>{
 const token=await start(db);await db.exec("update storage.objects set bucket_id='unreviewed'");assert.equal(await rpc(db,'media_backup_manifest',[token]),null);
 assert.equal((await db.query('select last_error from media_backup.control')).rows[0].last_error,'INVENTORY_INCOMPLETE');
 await db.exec("update storage.objects set bucket_id='memory_photos',metadata='{}'");assert.equal(await rpc(db,'media_backup_manifest',[token]),null);
 await db.exec("update storage.objects set archived_at=now()");assert.equal((await rpc(db,'media_backup_manifest',[token])).missing,0);
}));
test('daily rollover resets only transfer allowance; stale jobs remain charged to storage',()=>fixture(async db=>{
 const token=await start(db);await rpc(db,'next_media_backup_work',[token]);
 await db.exec("update media_backup.control set day=current_date-1,copy_bytes=1000000000;update media_backup.copies set attempt_after=now()");
 const retry=await rpc(db,'next_media_backup_work',[token]);assert.equal(retry.kind,'copy');assert.equal((await db.query('select copy_bytes from media_backup.control')).rows[0].copy_bytes,100);
 assert.equal((await db.query('select count(*) n from media_backup.copies')).rows[0].n,1);
 await rpc(db,'finish_media_backup_run',[token,'SOURCE_FAILED',false]);assert.equal((await db.query('select last_error from media_backup.control')).rows[0].last_error,'SOURCE_FAILED');
}));
