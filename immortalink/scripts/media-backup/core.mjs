import {createHash} from 'node:crypto';

export const MAX_FILE_BYTES = 50 * 1024 * 1024;
const fingerprintPattern = /^[a-f0-9]{64}$/;
const buckets = new Set(['avatars','family_avatars','legacy_avatars','memory_photos','memory_voice',
  'vault_photos','vault_voice','legacy_memory_photos','legacy_memory_voice','legacy_vault_photos','legacy_vault_voice','voice notes']);
export function validateCopy(job) {
  if (!job || !fingerprintPattern.test(job.fingerprint) || !buckets.has(job.bucket) ||
      typeof job.object_name !== 'string' || job.object_name.length<1 || job.object_name.length>2048 ||
      !Number.isSafeInteger(job.byte_size) || job.byte_size<0 || job.byte_size>MAX_FILE_BYTES) throw new Error('VERIFY_FAILED');
  // URL dot-segment normalization must never escape the selected object.
  if (job.object_name.split('/').some(p=>p==='.' || p==='..') || /[\u0000-\u001f\u007f]/.test(job.object_name)) throw new Error('VERIFY_FAILED');
  return job;
}
export const digests = bytes => ({sha256:createHash('sha256').update(bytes).digest('hex'),md5:createHash('md5').update(bytes).digest('hex')});
export function objectKeys(fingerprint) {
  if (!fingerprintPattern.test(fingerprint)) throw new Error('VERIFY_FAILED');
  return {data:`objects/${fingerprint}.bin`,metadata:`objects/${fingerprint}.json`};
}
export async function readBounded(response, expected, maximum=MAX_FILE_BYTES) {
  if (!Number.isSafeInteger(expected) || expected<0 || expected>maximum) throw new Error('VERIFY_FAILED');
  if (!response.ok) throw new Error('SOURCE_FAILED');
  if (!response.body) {if(expected===0)return new Uint8Array(0);throw new Error('SOURCE_FAILED');}
  const announced=response.headers.get('content-length');
  if (announced!==null && Number(announced)!==expected) {await response.body.cancel();throw new Error('VERIFY_FAILED');}
  // A single bounded destination avoids holding an unbounded chunk list.
  const result=new Uint8Array(expected);let offset=0;const reader=response.body.getReader();
  try {while(true){const {done,value}=await reader.read();if(done)break;
    if(offset+value.byteLength>expected) throw new Error('VERIFY_FAILED');
    result.set(value,offset);offset+=value.byteLength;}
    if(offset!==expected)throw new Error('VERIFY_FAILED');
    return result;
  } finally {await reader.cancel().catch(()=>{});reader.releaseLock();}
}

function verifyHead(head, job, hash) {
  if (!head || head.size!==job.byte_size || head.sha256!==hash.sha256 || head.md5!==hash.md5 ||
      head.etag?.replaceAll('"','')!==hash.md5) throw new Error('VERIFY_FAILED');
}

export async function copyOne({job,source,destination,isCurrent,onStep=()=>{}}) {
  validateCopy(job);const keys=objectKeys(job.fingerprint);
  // Crash after PUT, before DB acknowledgement: validate and reuse the existing
  // immutable object instead of charging another source download.
  onStep('destination_head');const existing=await destination.head(keys.data);
  let hash;
  if (existing) {
    hash={sha256:existing.sha256,md5:existing.md5};
    if (!fingerprintPattern.test(hash.sha256??'') || !/^[a-f0-9]{32}$/.test(hash.md5??'')) throw new Error('VERIFY_FAILED');
    verifyHead(existing,job,hash);
  } else {
    onStep('source_current');if (!await isCurrent(job.fingerprint)) throw new Error('SOURCE_FAILED');
    onStep('source_download');
    const response=await source.download(job);
    const bytes=await readBounded(response,job.byte_size);
    onStep('checksum');hash=digests(bytes);
    // Do not attach new bytes to an old source version if an edit raced us.
    onStep('source_recheck');if (!await isCurrent(job.fingerprint)) throw new Error('SOURCE_FAILED');
    const sourceMd5=job.source_etag?.replaceAll('"','');
    if (/^[a-fA-F0-9]{32}$/.test(sourceMd5??'') && hash.md5!==sourceMd5.toLowerCase()) throw new Error('VERIFY_FAILED');
    onStep('destination_put');await destination.putBytes(keys.data,bytes,hash);
    onStep('destination_verify');
    verifyHead(await destination.head(keys.data),job,hash);
  }
  // Self-describing recovery sidecar; no database secret or download URL.
  onStep('sidecar');await destination.putJson(keys.metadata,{format:1,project:'vbzyvaylfdhwowdbodmk',
    fingerprint:job.fingerprint,object_id:job.object_id,bucket:job.bucket,object_name:job.object_name,
    source_updated_at:job.source_updated_at,byte_size:job.byte_size,...hash});
  return hash;
}

export async function runBackup({backend,source,destination,token,now=()=>Date.now(),onError=(_detail)=>{}}) {
  const started=now();let error=null,manifestSaved=false,copied=0,deleted=0;
  let stage='start';const onStep=value=>{stage=value;};
  const rpc=(name,args={})=>backend.rpc(name,{p_token:token,...args});
  try {
    // Small bounded batches leave room for hashing and uploads in Edge limits.
    for(let i=0;i<5 && now()-started<70000;i++) {
      stage='next_job';const job=await rpc('next_media_backup_work');if(!job)break;
      if(job.kind==='delete') {
        const keys=objectKeys(job.fingerprint);
        if(await rpc('media_backup_source_current',{p_fingerprint:job.fingerprint})) throw new Error('VERIFY_FAILED');
        await destination.remove(keys.data);await destination.remove(keys.metadata);
        if(!await rpc('complete_media_backup_work',{p_fingerprint:job.fingerprint}))throw new Error('BACKUP_UNAVAILABLE');
        deleted++;
      } else if(job.kind==='copy') {
        const hash=await copyOne({job,source,destination,onStep,isCurrent:fingerprint=>rpc('media_backup_source_current',{p_fingerprint:fingerprint})});
        stage='acknowledge';
        if(!await rpc('complete_media_backup_work',{p_fingerprint:job.fingerprint,p_sha256:hash.sha256,p_md5:hash.md5}))throw new Error('BACKUP_UNAVAILABLE');
        copied++;
      } else throw new Error('VERIFY_FAILED');
    }
    stage='manifest';const manifest=await rpc('media_backup_manifest');
    if(manifest && manifest.format===1 && manifest.missing===0 && Array.isArray(manifest.entries)) {
      const date=new Date(manifest.captured_at).toISOString().slice(0,10);
      await destination.putJson(`manifests/${date}.json`,manifest);
      await destination.putJson('status/latest.json',{format:1,completed_at:manifest.captured_at,objects:manifest.entries.length,
        manifest:`manifests/${date}.json`});
      manifestSaved=true;
    }
  } catch(e) {error=['SOURCE_FAILED','DESTINATION_FAILED','VERIFY_FAILED'].includes(e?.message)?e.message:'BACKUP_UNAVAILABLE';
    onError({stage,code:error,type:['ReferenceError','TypeError','RangeError','Error'].includes(e?.name)?e.name:'Other',
      reason:/^(Buffer|crypto|Deno|EdgeRuntime) is not defined$/.test(e?.message??'')?e.message:null});}
  await rpc('finish_media_backup_run',{p_error:error,p_manifest:manifestSaved});
  return {copied,deleted,manifestSaved,error};
}

/** @param {{enabled?:boolean,backend?:ReturnType<import('./transport.mjs').createSource>,source?:ReturnType<import('./transport.mjs').createSource>,destination?:ReturnType<import('./transport.mjs').createDestination>,waitUntil?:Function,run?:typeof runBackup,onError?:Function}} options */
export function createBackupHandler({enabled=false,backend,source,destination,waitUntil,run=runBackup,onError=()=>{}}={}) {
  const reply=(status,code)=>Response.json({code},{status,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
  return async request=>{
    if(!enabled||!backend||!source||!destination)return reply(503,'BACKUP_DISABLED');
    if(request.method!=='POST')return reply(405,'METHOD_NOT_ALLOWED');
    const token=request.headers.get('x-backup-run-token');
    if(!/^[a-f0-9]{64}$/.test(token??''))return reply(401,'UNAUTHORIZED');
    try {if(await backend.rpc('claim_media_backup_run',{p_token:token})!==true)return reply(401,'UNAUTHORIZED');}
    catch{return reply(503,'BACKUP_UNAVAILABLE');}
    const task=run({backend,source,destination,token,onError}).catch(()=>{});
    if(waitUntil)waitUntil(task);else await task;
    return reply(202,'BACKUP_ACCEPTED');
  };
}
