import {test} from 'node:test';import assert from 'node:assert/strict';import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {restoreEntry} from './restore.mjs';import {digests} from './core.mjs';
test('manual restore verifies bytes, cannot traverse paths or overwrite existing files',async()=>{
 const directory=await mkdtemp('/private/tmp/heiro-restore-test-'),bytes=new TextEncoder().encode('Generated recovery exercise.');
 const entry={fingerprint:'a'.repeat(64),bucket:'memory_photos',object_name:'a/nested/photo.jpg',byte_size:bytes.length,...digests(bytes)};
 const destination={getJson:async()=>entry,getBytes:async()=>bytes};
 try {
  assert.equal((await restoreEntry({destination,entry,directory})).bytes,bytes.length);
  assert.deepEqual(new Uint8Array(await readFile(directory+'/'+entry.fingerprint+'.bin')),bytes);
  await assert.rejects(restoreEntry({destination,entry,directory}),/EEXIST/);
  await assert.rejects(restoreEntry({destination,entry:{...entry,object_name:'../escape'},directory}),/VERIFY_FAILED/);
  await assert.rejects(restoreEntry({destination:{...destination,getBytes:async()=>new Uint8Array(bytes.length)},entry,directory}),/VERIFY_FAILED/);
 }finally{await rm(directory,{recursive:true,force:true});}
});
