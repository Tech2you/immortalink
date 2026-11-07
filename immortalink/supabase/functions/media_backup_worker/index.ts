import {AwsClient} from 'npm:aws4fetch@1.0.20';
import {createBackupHandler} from '../../../scripts/media-backup/core.mjs';
import {createSource,createDestination} from '../../../scripts/media-backup/transport.mjs';
declare const EdgeRuntime: {waitUntil(task:Promise<unknown>):void};
const enabled=Deno.env.get('HEIRO_MEDIA_BACKUP_ENABLED')==='true';
let backend, destination;
if(enabled) {
  try {
    backend=createSource({serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')});
    const accessKeyId=Deno.env.get('HEIRO_R2_ACCESS_KEY_ID');
    const secretAccessKey=Deno.env.get('HEIRO_R2_SECRET_ACCESS_KEY');
    if(!accessKeyId||!secretAccessKey)throw new Error('BACKUP_UNAVAILABLE');
    const client=new AwsClient({accessKeyId,secretAccessKey,region:'auto',service:'s3',retries:0});
    destination=createDestination({accountId:Deno.env.get('HEIRO_R2_ACCOUNT_ID'),bucket:Deno.env.get('HEIRO_R2_BUCKET'),
      sign:(url:string,init:RequestInit)=>client.sign(url,init)});
  } catch { /* Fail closed without logging secrets or private media paths. */ }
}
Deno.serve(createBackupHandler({enabled,backend,source:backend,destination,
  onError:(detail:unknown)=>console.error('media_backup_failure',JSON.stringify(detail)),
  waitUntil:(task:Promise<unknown>)=>EdgeRuntime.waitUntil(task)}));
