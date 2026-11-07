// Manual generated-data drill. Run with Deno and a protected environment file.
// No Supabase keys or family media are read by this check.
import {AwsClient} from 'npm:aws4fetch@1.0.20';
import {randomUUID,randomBytes} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {createDestination} from './transport.mjs';
import {copyOne,digests,objectKeys} from './core.mjs';
import {restoreEntry} from './restore.mjs';
const accessKeyId=Deno.env.get('HEIRO_R2_ACCESS_KEY_ID'),secretAccessKey=Deno.env.get('HEIRO_R2_SECRET_ACCESS_KEY');
if(!accessKeyId||!secretAccessKey)throw new Error('BACKUP_NOT_CONFIGURED');
const client=new AwsClient({accessKeyId,secretAccessKey,region:'auto',service:'s3',retries:0});
const accountId=Deno.env.get('HEIRO_R2_ACCOUNT_ID'),bucket=Deno.env.get('HEIRO_R2_BUCKET');
const destination=createDestination({accountId,bucket,sign:(url:string,init:RequestInit)=>client.sign(url,init)});
const bytes=new Uint8Array(randomBytes(65536)),hash=digests(bytes),fingerprint=digests(new TextEncoder().encode(randomUUID())).sha256;
const keys=objectKeys(fingerprint),directory=await mkdtemp('/private/tmp/heiro-r2-restore-');
const job={fingerprint,object_id:randomUUID(),bucket:'memory_photos',object_name:'generated-recovery-check.bin',source_updated_at:new Date().toISOString(),byte_size:bytes.length,source_etag:hash.md5};
try {
 await copyOne({job,source:{download:async()=>new Response(bytes)},destination,isCurrent:async()=>true});
 const restored=await restoreEntry({destination,entry:{...job,...hash},directory});
 if(restored.sha256!==hash.sha256)throw new Error('RESTORE_FAILED');
 const unauth=await fetch(`https://${accountId}.r2.cloudflarestorage.com/${bucket}/${keys.data}`,{redirect:'error'});
 const denial=await unauth.text();
 if(![401,403].includes(unauth.status)&&!(unauth.status===400&&denial.includes('<Code>InvalidArgument</Code>')&&denial.includes('<Message>Authorization</Message>')))throw new Error('PUBLIC_ACCESS_CHECK_FAILED');
 console.log(JSON.stringify({generated_bytes:bytes.length,restore_verified:true,unauthenticated_status:unauth.status}));
}finally{await destination.remove(keys.data);await destination.remove(keys.metadata);await rm(directory,{recursive:true,force:true});console.log('Generated test data removed from R2 and local recovery folder.');}
