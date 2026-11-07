// Bound the stream itself: Content-Length is optional and not trustworthy.
export async function readBoundedJson(req:Request, maximum:number):Promise<Record<string,unknown>> {
  if(!req.body) throw new Error('EMPTY_BODY');
  const reader=req.body.getReader(); const parts:Uint8Array[]=[]; let length=0;
  try { while(true) { const {value,done}=await reader.read(); if(done)break;
    length+=value.length; if(length>maximum)throw new Error('BODY_TOO_LARGE'); parts.push(value);
  }} finally { await reader.cancel(); }
  const bytes=new Uint8Array(length); let offset=0;
  for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  const value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
  if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('INVALID_BODY');
  return value;
}
