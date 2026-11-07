import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

// Reproducible local packaging only. No credentials, API requests or deployment.
const root=new URL('../../',import.meta.url), output=new URL('build/content-screening-deploy/',root);
const copy=async path=>{const target=new URL(path,output);await mkdir(new URL('.',target),{recursive:true});await copyFile(new URL(path,root),target);};
for(const path of [
  'supabase/functions/process_content_screening/index.ts',
  'supabase/functions/prepare_screening_photo/index.ts','supabase/functions/prepare_screening_photo/binary.json',
  'supabase/functions/_shared/content_screening.mjs',
  ...['backend','worker','worker_transport','content_batch','photo_transport','photo_job','photo_wasm','photo_container','bundled_normalizer'].map(name=>`scripts/content-screening/${name}.mjs`),
])await copy(path);
const target=new URL('supabase/functions/prepare_screening_photo/',output);
const module=new URL(import.meta.resolve('@imagemagick/magick-wasm'));
const binary=await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')));
const expected=JSON.parse(await readFile(new URL('binary.json',target),'utf8'));
if(binary.length!==expected.bytes || createHash('sha256').update(binary).digest('hex')!==expected.sha256)throw Error('PINNED_DECODER_MISMATCH');
await writeFile(new URL('magick.wasm',target),binary);
await copyFile(module,new URL('magick.mjs',target));
for(const name of ['LICENSE','NOTICE'])await copyFile(new URL(`../${name}`,module),new URL(`MAGICK-${name}`,target));
const imports={'@imagemagick/magick-wasm':'./magick.mjs'};
await writeFile(new URL('deno.json',target),JSON.stringify({imports},null,2));
await writeFile(new URL('supabase/config.toml',output),`project_id = "vbzyvaylfdhwowdbodmk"
[functions.process_content_screening]
verify_jwt = false
[functions.prepare_screening_photo]
verify_jwt = true
import_map = "./functions/prepare_screening_photo/deno.json"
static_files = ["./functions/prepare_screening_photo/magick.wasm", "./functions/prepare_screening_photo/MAGICK-LICENSE", "./functions/prepare_screening_photo/MAGICK-NOTICE"]
`);
console.log('Prepared disabled-by-default screening deployment bundle. No deployment performed.');
