// Read recovery metadata and HEAD checks only; never download family media.
import {AwsClient} from 'npm:aws4fetch@1.0.20';
import {createDestination} from './transport.mjs';
import {objectKeys} from './core.mjs';
const accessKeyId=Deno.env.get('HEIRO_R2_ACCESS_KEY_ID'),secretAccessKey=Deno.env.get('HEIRO_R2_SECRET_ACCESS_KEY');
if(!accessKeyId||!secretAccessKey)throw new Error('BACKUP_NOT_CONFIGURED');
const client=new AwsClient({accessKeyId,secretAccessKey,region:'auto',service:'s3',retries:0});
const destination=createDestination({accountId:Deno.env.get('HEIRO_R2_ACCOUNT_ID'),bucket:Deno.env.get('HEIRO_R2_BUCKET'),sign:(url:string,init:RequestInit)=>client.sign(url,init)});
const status=await destination.getJson('status/latest.json');
const inventory=await destination.getJson(status.manifest);
if(inventory.missing!==0||inventory.entries.length!==status.objects)throw new Error('INCOMPLETE_INVENTORY');
if(inventory.entries.length>1000)throw new Error('REVIEW_LARGE_INVENTORY_FIRST');
let bytes=0;
for(const entry of inventory.entries){
 const head=await destination.head(objectKeys(entry.fingerprint).data);
 if(!head||head.size!==entry.byte_size||head.sha256!==entry.sha256||head.md5!==entry.md5||head.etag?.replaceAll('"','')!==entry.md5)throw new Error('VERIFY_FAILED');
 bytes+=entry.byte_size;
}
console.log(JSON.stringify({completed_at:status.completed_at,verified_objects:inventory.entries.length,verified_bytes:bytes,media_downloaded:false}));
