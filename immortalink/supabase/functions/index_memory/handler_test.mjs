// Real handler with synthetic authorization fixtures; no customer data.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {readBoundedJson} from '../_shared/bounded_json.ts';
const source=stripTypeScriptTypes(readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
const vault='00000000-0000-4000-8000-000000000001',memory='00000000-0000-4000-8000-000000000002';
function fixture(options={}) {
 let handler;const calls=[],filters={};
 const caller={auth:{getUser:async()=>options.signedOut?{error:true}:{data:{user:{id:'viewer'}}}},from(table){assert.equal(table,'memories');return {
  select(fields){assert.equal(fields,'id');return this;},eq(k,v){filters[k]=v;return this;},
  maybeSingle:async()=>({data:options.denied?null:{id:memory},error:options.readError})
 };}};
 const admin={rpc:async(name,args)=>{calls.push({name,args});return {data:{chunk_count:1,unchanged:false},error:options.rpcError};}};
 new Function('serve','createClient','Deno','readBoundedJson',source)(fn=>handler=fn,(_url,key,opts)=>{
  if(key==='anon'){assert.equal(opts.global.headers.Authorization,'Bearer fixture');return caller;}
  assert.equal(key,'service');return admin;
 },{env:{get:key=>key==='SUPABASE_ANON_KEY'?'anon':key==='SUPABASE_SERVICE_ROLE_KEY'?'service':'https://fixture'}},readBoundedJson);
 return {calls,filters,async ask(body={vault_id:vault,memory_id:memory}){const response=await handler(new Request('https://fixture',{method:'POST',headers:{authorization:'Bearer fixture'},body:typeof body==='string'?body:JSON.stringify(body)}));return {status:response.status,body:await response.json()};}};
}
test('unauthorized, blocked and unavailable memory reads never invoke privileged indexing',async()=>{
 for(const [opts,status] of [[{signedOut:true},401],[{denied:true},403],[{readError:true},503]]){
  const f=fixture(opts);assert.equal((await f.ask()).status,status);assert.equal(f.calls.length,0);
 }
});
test('valid request binds caller, vault and memory; caller text is never forwarded',async()=>{
 const f=fixture();assert.equal((await f.ask({vault_id:vault,memory_id:memory,body:'forged chunks'})).status,200);
 assert.deepEqual(f.filters,{id:memory,vault_id:vault});
 assert.deepEqual(f.calls,[{name:'rebuild_memory_index',args:{p_actor:'viewer',p_vault:vault,p_memory:memory}}]);
});
test('invalid IDs and oversized bodies cannot reach privileged indexing',async()=>{
 for(const body of [{vault_id:'bad',memory_id:memory},'x'.repeat(3000),'[]','not-json']){
  const f=fixture();assert.equal((await f.ask(body)).status,400);assert.equal(f.calls.length,0);
 }
});
test('limit errors are actionable; database internals are never returned',async()=>{
 for(const [message,status] of [['INDEX_RATE_LIMIT',429],['INDEX_TEXT_LIMIT',422],['secret database details',503]]){
  const f=fixture({rpcError:{message}}),r=await f.ask();assert.equal(r.status,status);assert.doesNotMatch(JSON.stringify(r.body),/secret database/);
 }
});
