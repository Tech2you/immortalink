import {test} from 'node:test';import assert from 'node:assert/strict';
import {setup,index,actor,vault,memory} from './helpers/launch_security_fixture.mjs';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
async function fixture(fn){const db=new PGlite();try{await setup(db);await fn(db);}finally{await db.close();}}
test('server text bounds cover insert and update, preserve saved rows and normal saves',()=>fixture(async db=>{
 assert.equal((await db.query('select body from memories')).rows[0].body,'Saved original story');
 for(const [table,column,max] of [['memories','body',50000],['legacy_memories','body',50000],['vaults','about_me_text',10000],['legacy_family_members','about_me_text',10000],['memory_voice_notes','transcript',20000],['legacy_memory_voice_notes','title',500]]){
  await assert.rejects(db.query(`insert into ${table}(${column}) values($1)`,['x'.repeat(max+1)]),/TEXT_LIMIT_EXCEEDED/);
 }
 await db.query('update memories set body=$1',['x'.repeat(50000)]);
 await assert.rejects(db.query('update memories set body=$1',['x'.repeat(50001)]),/TEXT_LIMIT_EXCEEDED/);
 assert.equal((await db.query('select length(body) n from memories')).rows[0].n,50000);
}));
test('indexing uses trusted source, includes all voices, skips unchanged and replaces empty source',()=>fixture(async db=>{
 await db.query('insert into memory_voice_notes(vault_id,memory_id,title,transcript) values($1,$2,$3,$4)',[vault,memory,'Recording','Saved voice']);
 assert.equal((await index(db)).rows[0].result.unchanged,false);
 const first=(await db.query('select * from memory_chunks')).rows;
 assert.match(first[0].chunk_text,/Saved original story/);assert.match(first[0].chunk_text,/Saved voice/);
 assert.equal((await index(db)).rows[0].result.unchanged,true);
 assert.deepEqual((await db.query('select * from memory_chunks')).rows,first);
 await db.exec("update memories set body='',prompt_text='';delete from memory_voice_notes");
 assert.equal((await index(db)).rows[0].result.chunk_count,0);
 assert.equal((await db.query('select * from memory_chunks')).rows.length,0);
}));
test('failed replacement rolls back delete; oversized and rate limited indexing preserve old index',()=>fixture(async db=>{
 await index(db);const before=(await db.query('select * from memory_chunks')).rows;
 await db.exec("update memories set body='Changed';create function fail_index() returns trigger language plpgsql as $$begin raise exception 'TEST_WRITE_FAILURE';end$$;create trigger fail_index before insert on memory_chunks for each row execute function fail_index()");
 await assert.rejects(index(db),/TEST_WRITE_FAILURE/);
 assert.deepEqual((await db.query('select * from memory_chunks')).rows,before);
 await db.exec('drop trigger fail_index on memory_chunks;update heiro_security.index_rate set minute_count=120');
 await assert.rejects(index(db),/INDEX_RATE_LIMIT/);
 await db.exec('update heiro_security.index_rate set minute_count=0');
 await db.query("insert into memory_voice_notes(vault_id,memory_id,transcript) select $1,$2,repeat('x',20000) from generate_series(1,10)",[vault,memory]);
 await assert.rejects(index(db),/INDEX_TEXT_LIMIT/);
 assert.deepEqual((await db.query('select * from memory_chunks')).rows,before);
}));
test('client roles cannot forge indexes, reserve/refund AI budget, or read private ledgers',()=>fixture(async db=>{
 for(const role of ['anon','authenticated']){
  await db.exec(`set role ${role}`);
  await assert.rejects(index(db),/permission denied/);
  await assert.rejects(db.query("select reserve_ai_budget('chat',1)"),/permission denied/);
  await assert.rejects(db.query('select settle_ai_budget($1,0)',[actor]),/permission denied/);
  await assert.rejects(db.query('select * from heiro_security.ai_budget_settings'),/permission denied/);
  await db.exec('reset role');
 }
 await assert.rejects(db.query('select rebuild_memory_index($1,$2,$3)',[vault,vault,memory]),/INDEX_ACCESS_DENIED/);
}));
test('budget enforces exact ceiling, releases only once, keeps unknown charges, rolls days independently',()=>fixture(async db=>{
 const reserve=async amount=>(await db.query("select reserve_ai_budget('chat',$1) id",[amount])).rows[0].id;
 const token=await reserve(200000);for(let i=0;i<9;i++)assert.ok(await reserve(200000));
 assert.equal(await reserve(1),null);
 await db.query('select settle_ai_budget($1,100000)',[token]);await db.query('select settle_ai_budget($1,0)',[token]);
 assert.equal((await db.query('select reserved_microdollars n from heiro_security.ai_budget_days')).rows[0].n,1900000);
 assert.ok(await reserve(100000));assert.equal(await reserve(1),null);
 await db.exec("insert into heiro_security.ai_budget_days values(current_date-1,2000000,0,0)");
 assert.equal((await db.query('select count(*) n from heiro_security.ai_budget_days')).rows[0].n,2);
 await assert.rejects(reserve(-1),/INVALID_AI_RESERVATION/);
}));
test('unexpected provider cost trips the safety switch and owner stats stay private',()=>fixture(async db=>{
 const token=(await db.query("select reserve_ai_budget('chat',100) id")).rows[0].id;
 await db.query('select settle_ai_budget($1,101)',[token]);
 assert.equal((await db.query("select reserve_ai_budget('chat',1) id")).rows[0].id,null);
 assert.equal((await db.query('select pricing_mismatches n from heiro_security.ai_budget_days')).rows[0].n,1);
 await assert.rejects(db.query('select business_ai_budget_status()'),/BUSINESS_ACCESS_DENIED/);
}));
