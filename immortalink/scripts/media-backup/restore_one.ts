// Manual recovery to a NEW LOCAL directory, never into production storage.
// Arguments: 64-character object fingerprint, destination directory.
import {AwsClient} from 'npm:aws4fetch@1.0.20';
import {createDestination} from './transport.mjs';
import {objectKeys} from './core.mjs';
import {restoreEntry} from './restore.mjs';
const [fingerprint,directory]=Deno.args;
if(!directory)throw new Error('Provide fingerprint and a local destination directory.');
const keys=objectKeys(fingerprint);
const accessKeyId=Deno.env.get('HEIRO_R2_ACCESS_KEY_ID'),secretAccessKey=Deno.env.get('HEIRO_R2_SECRET_ACCESS_KEY');
if(!accessKeyId||!secretAccessKey)throw new Error('BACKUP_NOT_CONFIGURED');
const client=new AwsClient({accessKeyId,secretAccessKey,region:'auto',service:'s3',retries:0});
const destination=createDestination({accountId:Deno.env.get('HEIRO_R2_ACCOUNT_ID'),bucket:Deno.env.get('HEIRO_R2_BUCKET'),sign:(url:string,init:RequestInit)=>client.sign(url,init)});
const entry=await destination.getJson(keys.metadata);
if(entry.fingerprint!==fingerprint)throw new Error('VERIFY_FAILED');
console.log(JSON.stringify(await restoreEntry({destination,entry,directory})));
