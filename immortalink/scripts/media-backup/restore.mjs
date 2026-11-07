import {mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {digests,objectKeys,validateCopy} from './core.mjs';

// Restore only to a new local directory. Never overwrite app/source storage or
// trust a saved object's path as a local filesystem path.
export async function restoreEntry({destination,entry,directory}) {
 validateCopy(entry);const keys=objectKeys(entry.fingerprint);
 const metadata=await destination.getJson(keys.metadata);
 for(const field of ['fingerprint','bucket','object_name','byte_size','sha256','md5'])if(metadata[field]!==entry[field])throw new Error('VERIFY_FAILED');
 const bytes=await destination.getBytes(keys.data,entry.byte_size),hash=digests(bytes);
 if(hash.sha256!==entry.sha256||hash.md5!==entry.md5)throw new Error('VERIFY_FAILED');
 await mkdir(directory,{recursive:true,mode:0o700});
 await writeFile(resolve(directory,entry.fingerprint+'.bin'),bytes,{mode:0o600,flag:'wx'});
 await writeFile(resolve(directory,entry.fingerprint+'.json'),JSON.stringify(metadata,null,2),{mode:0o600,flag:'wx'});
 return {bytes:bytes.length,sha256:hash.sha256};
}
