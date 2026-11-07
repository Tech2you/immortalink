import { createHash } from 'node:crypto';
import { createScreeningBackend } from '../../../scripts/content-screening/backend.mjs';
import { createPhotoPreparationHandler } from '../../../scripts/content-screening/photo_transport.mjs';
import { createBundledNormalizerLoader } from '../../../scripts/content-screening/bundled_normalizer.mjs';
import { createWasmPhotoPreparer } from '../../../scripts/content-screening/photo_wasm.mjs';
import binary from './binary.json' with { type: 'json' };

const enabled = Deno.env.get('HEIRO_CONTENT_SCREENING_ENABLED') === 'true';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const token = serviceKey ? createHash('sha256').update(`heiro-screening-photo:${serviceKey}`).digest('hex') : '';
const load = createBundledNormalizerLoader({ ...binary,
  readBinary: () => Deno.readFile(new URL('./magick.wasm', import.meta.url)),
  createPreparer: createWasmPhotoPreparer,
});
Deno.serve(createPhotoPreparationHandler({
  enabled,
  workerTokenSha256: token ? createHash('sha256').update(token).digest('hex') : undefined,
  backend: serviceKey ? createScreeningBackend({ serviceKey }) : undefined,
  normalize: async (bytes: Uint8Array, mime: string) => (await load())(bytes, mime),
}));
