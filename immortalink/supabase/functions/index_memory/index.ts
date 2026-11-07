import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
import { readBoundedJson } from "../_shared/bounded_json.ts";
const headers = {"Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS", "Content-Type":"application/json", "Cache-Control":"no-store"};
const json = (status:number, body:unknown) => new Response(JSON.stringify(body),{status,headers});
const uuid = (v:unknown) => typeof v==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
serve(async req => {
  if(req.method==='OPTIONS') return new Response(null,{status:204,headers});
  if(req.method!=='POST') return json(405,{error:'Use POST'});
  try {
    const caller=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,
      {global:{headers:{Authorization:req.headers.get('authorization')||''}},auth:{persistSession:false}});
    const {data:user,error:authError}=await caller.auth.getUser();
    if(authError||!user?.user) return json(401,{error:'Please sign in again.'});
    const {vault_id,memory_id}=await readBoundedJson(req,2048);
    if(!uuid(vault_id)||!uuid(memory_id)) return json(400,{error:'A valid vault and memory are required.'});
    const {data:memory,error}=await caller.from('memories').select('id').eq('id',memory_id).eq('vault_id',vault_id).maybeSingle();
    if(error) return json(503,{error:'Memory indexing is temporarily unavailable.'});
    if(!memory) return json(403,{error:'Not allowed or not found.'});
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
    const result=await admin.rpc('rebuild_memory_index',{p_actor:user.user.id,p_vault:vault_id,p_memory:memory_id});
    if(result.error) {
      const code=result.error.message;
      if(code==='INDEX_RATE_LIMIT') return json(429,{error:'Please wait before refreshing the memory index again.'});
      if(code==='INDEX_TEXT_LIMIT') return json(422,{error:'This memory has too much text to index. Your saved memory is unchanged.'});
      return json(503,{error:'Memory indexing is temporarily unavailable. Your saved memory is unchanged.'});
    }
    return json(200,result.data);
  } catch { return json(400,{error:'Unable to read this indexing request.'}); }
});
