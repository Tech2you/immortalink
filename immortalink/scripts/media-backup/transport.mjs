import {digests,readBounded,validateCopy} from './core.mjs';
import {Buffer} from 'node:buffer';
const projectOrigin='https://vbzyvaylfdhwowdbodmk.supabase.co';
const allowedRpc=new Set(['claim_media_backup_run','next_media_backup_work','complete_media_backup_work',
  'media_backup_manifest','media_backup_source_current','finish_media_backup_run']);

export function createSource({serviceKey,fetcher=fetch}) {
  if(!serviceKey)throw new Error('BACKUP_UNAVAILABLE');
  const headers={'apikey':serviceKey,'authorization':`Bearer ${serviceKey}`};
  return {
    async rpc(name,args){
      if(!allowedRpc.has(name))throw new Error('BACKUP_UNAVAILABLE');
      const response=await fetcher(`${projectOrigin}/rest/v1/rpc/${name}`,{method:'POST',headers:{...headers,'content-type':'application/json'},
        body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(20000)});
      if(!response.ok)throw new Error('BACKUP_UNAVAILABLE');return response.json();
    },
    async download(job){
      validateCopy(job);
      const path=[job.bucket,...job.object_name.split('/')].map(encodeURIComponent).join('/');
      const response=await fetcher(`${projectOrigin}/storage/v1/object/authenticated/${path}`,{
        method:'GET',headers,redirect:'error',signal:AbortSignal.timeout(40000)});
      if(!response.ok) {await response.body?.cancel();throw new Error('SOURCE_FAILED');}return response;
    },
  };
}

// sign is supplied by the pinned, vendor-documented aws4fetch package. Neither
// caller payloads nor source metadata can select a network destination.
export function createDestination({accountId,bucket,sign,fetcher=fetch}) {
  if(!/^[a-f0-9]{32}$/.test(accountId??'')||!/^heiro-media-backup-[a-z0-9-]{1,40}$/.test(bucket??'')||typeof sign!=='function')throw new Error('BACKUP_UNAVAILABLE');
  const origin=`https://${accountId}.r2.cloudflarestorage.com`;
  async function send(method,key,{body,headers={}}={}) {
    if(!/^(objects\/[a-f0-9]{64}\.(bin|json)|manifests\/\d{4}-\d{2}-\d{2}\.json|status\/latest\.json|checks\/[a-f0-9-]{36}\.(bin|json))$/.test(key))throw new Error('VERIFY_FAILED');
    const request=await sign(`${origin}/${bucket}/${key}`,{method,body,headers:{...headers,'accept-encoding':'identity','x-amz-content-sha256':'UNSIGNED-PAYLOAD'},
      redirect:'error',signal:AbortSignal.timeout(40000)});
    const response=await fetcher(request);
    if(!response.ok && !(method==='HEAD' && response.status===404) && !(method==='DELETE' && response.status===404)) {
      await response.body?.cancel();throw new Error('DESTINATION_FAILED');
    }
    return response;
  }
  async function put(key,bytes,hash,contentType){
    const response=await send('PUT',key,{body:bytes,headers:{'content-type':contentType,'cache-control':'private, no-store, no-transform',
      'content-md5':Buffer.from(hash.md5,'hex').toString('base64'),'x-amz-meta-sha256':hash.sha256,'x-amz-meta-md5':hash.md5,
      ...(key.startsWith('objects/')&&key.endsWith('.bin')?{'if-none-match':'*'}:{})}});
    await response.body?.cancel();
  }
  return {
    async head(key){const r=await send('HEAD',key);if(r.status===404)return null;
      if(r.headers.get('content-length')===null)throw new Error('VERIFY_FAILED');
      return {size:Number(r.headers.get('content-length')),etag:r.headers.get('etag'),sha256:r.headers.get('x-amz-meta-sha256'),md5:r.headers.get('x-amz-meta-md5')};},
    putBytes:(key,bytes,hash)=>put(key,bytes,hash,'application/octet-stream'),
    async putJson(key,value){const bytes=new TextEncoder().encode(JSON.stringify(value));if(bytes.length>(key.startsWith('objects/')?16384:8388608))throw new Error('VERIFY_FAILED');
      return put(key,bytes,digests(bytes),'application/json');},
    async remove(key){if(!key.startsWith('objects/')&&!key.startsWith('checks/'))throw new Error('VERIFY_FAILED');
      const r=await send('DELETE',key);await r.body?.cancel();},
    async getBytes(key,expected){return readBounded(await send('GET',key),expected);},
    async getJson(key){const info=await this.head(key);if(!info||info.size>8388608)throw new Error('VERIFY_FAILED');
      const bytes=await readBounded(await send('GET',key),info.size,8388608);
      const hash=digests(bytes);if(hash.sha256!==info.sha256||hash.md5!==info.md5)throw new Error('VERIFY_FAILED');
      return JSON.parse(new TextDecoder().decode(bytes));},
  };
}
