// Verified 2026-11-05: developers.openai.com/api/docs/pricing and model limits.
// Rates are micro-USD/token, doubled for a conservative safety margin. No caching
// discounts assumed. This controls these handlers, not other uses of the API key.
export class AiBudgetError extends Error {
  constructor() { super('AI is temporarily paused by the daily safety limit. Your memories are safe. Please try again later.'); }
}
type Kind = 'chat'|'embedding'|'transcription';
type Client = { rpc:(name:string,args:Record<string,unknown>)=>PromiseLike<{data?:unknown,error?:unknown}> };
const bytes=(value:unknown)=>new TextEncoder().encode(JSON.stringify(value)).length;
export function reservationCost(kind:Kind,body?:any):number {
  if(kind==='transcription') return 120000; // 16K input at <=$3/M + 2K output at $5/M, doubled.
  const size=bytes(body);
  if(size>200000) throw new AiBudgetError();
  if(kind==='embedding') {
    if(body?.model!=='text-embedding-3-small'||!Array.isArray(body.input)||body.input.some((x:unknown)=>typeof x!=='string')) throw new AiBudgetError();
    return Math.ceil((size+2048)*0.02*2);
  }
  if(body?.model!=='gpt-4o-mini'||!Number.isInteger(body.max_tokens)||body.max_tokens<1||body.max_tokens>260) throw new AiBudgetError();
  return Math.ceil(((size+2048)*0.15+body.max_tokens*0.60)*2);
}
export function settledCost(kind:Kind,usage:any):number|null {
  const valid=(n:unknown)=>Number.isSafeInteger(n)&&Number(n)>=0;
  if(kind==='embedding')return valid(usage?.total_tokens)?Math.ceil(usage.total_tokens*0.02*2):null;
  const input=kind==='chat'?usage?.prompt_tokens:usage?.input_tokens;
  const output=kind==='chat'?usage?.completion_tokens:usage?.output_tokens;
  if(!valid(input)||!valid(output))return null;
  return Math.ceil((input*(kind==='chat'?0.15:3)+output*(kind==='chat'?0.60:5))*2);
}
export async function reserveBudget(client:Client,kind:Kind,body?:unknown) {
  let result;
  try {result=await client.rpc('reserve_ai_budget',{p_kind:kind,p_amount:reservationCost(kind,body)});} catch {throw new AiBudgetError();}
  if(result.error||typeof result.data!=='string'||!result.data)throw new AiBudgetError();
  let started=false;
  return {
    // May only be called for a request that has never been dispatched.
    async cancelUnstarted(){
      if(!started){
        started=true;
        // A failed refund must keep the conservative reserve, but must not stop
        // the caller releasing an unstarted transcription claim.
        try { await client.rpc('settle_ai_budget',{p_id:result.data,p_amount:0}); } catch { /* Keep reservation. */ }
      }
    },
    async run(send:()=>Promise<Response>):Promise<any>{
      if(started)throw new AiBudgetError(); started=true;
      // Keep the entire reservation on HTTP errors, timeouts, malformed JSON or
      // absent usage. None of those safely proves that no charge occurred.
      const response=await send();
      if(!response.ok)throw new Error('AI_PROVIDER_UNAVAILABLE');
      const data=await response.json();
      const amount=settledCost(kind,data?.usage);
      if(amount!==null) {
        try { await client.rpc('settle_ai_budget',{p_id:result.data,p_amount:amount}); } catch { /* Keep reservation. */ }
      }
      return data;
    }
  };
}
export async function budgetedJson(client:Client,kind:Kind,body:unknown,send:()=>Promise<Response>) {
  return await (await reserveBudget(client,kind,body)).run(send);
}
