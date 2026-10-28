const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function readNotificationPayload(request) {
  const reader=request.body?.getReader();
  if(!reader) throw new Error('INVALID_REQUEST');
  const chunks=[];let length=0;
  try {
    while(true) {
      const {done,value}=await reader.read();
      if(done) break;
      length+=value.byteLength;
      if(length>4096) { await reader.cancel(); throw new Error('INVALID_REQUEST'); }
      chunks.push(value);
    }
  }finally{reader.releaseLock();}
  const bytes=new Uint8Array(length);let offset=0;
  for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  const payload=JSON.parse(new TextDecoder().decode(bytes));
  const type=payload?.type;
  const target=type==='memory_added'?payload.memory_id:type==='family_joined'?payload.family_id:null;
  if(!['memory_added','family_joined'].includes(type) || typeof target!=='string' || !uuid.test(target))
    throw new Error('INVALID_REQUEST');
  return {type,target};
}

export async function claimNotification(admin,{type,target},actorId) {
  const {data,error}=await admin.rpc('claim_family_notification',{p_type:type,p_target:target,p_actor:actorId});
  if(error) throw new Error('Notification eligibility unavailable');
  if(data?.allowed===false && ['DENIED','DUPLICATE','RATE_LIMIT','OUTBOX'].includes(data.code)) return {code:data.code};
  if(data?.allowed!==true || !uuid.test(data.family_id??'') || !Array.isArray(data.recipient_ids)
    || data.recipient_ids.some(id=>typeof id!=='string' || !uuid.test(id) || id===actorId))
    throw new Error('Invalid notification audience');
  return {code:'CLAIMED',familyId:data.family_id,recipientIds:[...new Set(data.recipient_ids)]};
}

export async function recipientTokens(admin,recipientIds) {
  const tokens=new Set();
  const signal=AbortSignal.timeout(20000);
  for(let i=0;i<recipientIds.length;i+=50) {
    let after=null;
    while(true) {
      let query=admin.from('user_push_tokens').select('token')
        .in('user_id',recipientIds.slice(i,i+50)).order('token').limit(200);
      if(after!==null) query=query.gt('token',after);
      const {data,error}=await query.abortSignal(signal);
      if(error || !Array.isArray(data)) throw new Error('Notification tokens unavailable');
      for(const row of data) {
        if(typeof row.token!=='string' || !row.token) throw new Error('Invalid notification token');
        tokens.add(row.token);
      }
      if(data.length<200) break;
      const last=data.at(-1).token;
      if(last===after) throw new Error('Notification pagination stalled');
      after=last;
    }
  }
  return [...tokens];
}

// Push is best effort: bound both concurrent requests and the dispatch window.
export async function sendBounded(tokens,send,{now=()=>performance.now(),budgetMs=90000}={}) {
  let next=0,sent=0,failed=0;
  const deadline=now()+budgetMs;
  await Promise.all(Array.from({length:Math.min(5,tokens.length)},async()=>{
    while(next<tokens.length && now()<deadline) {
      const token=tokens[next++];
      try {await send(token);sent++;}catch{failed++;}
    }
  }));
  return {sent,failed,skipped:tokens.length-next};
}
