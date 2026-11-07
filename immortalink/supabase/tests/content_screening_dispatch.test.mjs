import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {reviewFixture} from './helpers/screening_review_fixture.mjs';
import {request,rpc} from './helpers/screening_fixture.mjs';
import {owner} from './helpers/retirement_fixture.mjs';
import {asUser} from './helpers/publication_fixture.mjs';
const compatibility=await readFile(new URL('../migrations/20261105172337_content_screening_launch_compatibility.sql',import.meta.url),'utf8');
const dispatch=await readFile(new URL('../migrations/20261105173918_content_screening_worker_dispatch.sql',import.meta.url),'utf8');
export async function dispatchFixture(db){
  db=await reviewFixture(db);await db.exec(compatibility);
  await asUser(db,owner,'select set_content_screening_permission(true,$1,$2)',['openai-safety-text-photo-2026-11-05',owner]);
  await db.exec(`create schema net;create table net.requests(id bigint generated always as identity,url text,headers jsonb,body jsonb,timeout_ms integer);
    create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language sql as $$
      insert into net.requests(url,headers,body,timeout_ms) values($1,$2,$3,$4) returning id; $$;`);
  await db.exec(dispatch);return db;
}
test('default-off dispatcher uses single-use bounded invitations; callers cannot mint them',async t=>{
  const db=await dispatchFixture();t.after(()=>db.close());
  await request(db);assert.equal(await rpc(db,'dispatch_content_screening()'),null);
  await assert.rejects(asUser(db,owner,'select dispatch_content_screening()'),/permission denied/);
  await assert.rejects(asUser(db,owner,'select * from content_safety.screening_runs'),/permission denied/);
  await db.exec('update content_safety.screening_worker_config set enabled=true');
  const id=await rpc(db,'dispatch_content_screening()');assert.equal(typeof id,'number');
  const row=(await db.query('select * from net.requests where id=$1',[id])).rows[0];
  assert.equal(row.url,'https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/process_content_screening');
  assert.deepEqual(row.body,{});assert.equal(row.timeout_ms,10000);
  assert.deepEqual(Object.keys(row.headers).sort(),['Content-Type','x-screening-run-token']);
  const token=row.headers['x-screening-run-token'];assert.match(token,/^[a-f0-9]{64}$/);
  assert.equal(await rpc(db,'dispatch_content_screening()'),null);
  assert.equal(await rpc(db,'claim_screening_run($1)',[token]),true);
  assert.equal(await rpc(db,'claim_screening_run($1)',[token]),false);
  assert.equal(await rpc(db,'claim_screening_run($1)',['b'.repeat(64)]),false);
  assert.equal(await rpc(db,'finish_screening_run($1)',['b'.repeat(64)]),false);
  assert.equal(await rpc(db,'finish_screening_run($1)',[token]),true);
  assert.equal(await rpc(db,'finish_screening_run($1)',[token]),false);
});
test('expired invitations and daily budget stop repeated work; wake failure does not lose saves',async t=>{
  const db=await dispatchFixture();t.after(()=>db.close());
  await db.exec('update content_safety.screening_worker_config set enabled=true,max_daily_runs=1');
  await request(db);
  const token=(await db.query('select headers from net.requests')).rows[0].headers['x-screening-run-token'];
  await db.exec("update content_safety.screening_runs set expires_at=now()-interval '1 minute'");
  assert.equal(await rpc(db,'claim_screening_run($1)',[token]),false);
  assert.equal(await rpc(db,'dispatch_content_screening()'),null);
  await db.exec(`update content_safety.screening_worker_config set runs=0;
    create or replace function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language plpgsql as $$begin raise exception 'offline';end;$$;
    update content_safety.screening_jobs set state='queued',available_at=now();`);
  assert.equal((await db.query('select count(*)::int n from content_safety.screening_jobs')).rows[0].n,1);
  assert.equal((await db.query('select runs from content_safety.screening_worker_config')).rows[0].runs,0);
});
