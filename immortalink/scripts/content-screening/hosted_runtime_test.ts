import { createScreeningBackend } from './backend.mjs';
import { createPhotoPreparationHandler, createRemotePhotoPreparer } from './photo_transport.mjs';
import { photoDigest } from './photo_job.mjs';

Deno.test('production transports need no Node Buffer global in the hosted runtime', async () => {
  const globals = globalThis as unknown as { Buffer?: unknown };
  const previous = globals.Buffer;
  const id = '11111111-1111-4111-8111-111111111111', revision = 'a'.repeat(64);
  const token = 'local-test-only-'.repeat(3);
  const jpeg = new Uint8Array([255,216,255,224,1,2,255,217]);
  try {
    globals.Buffer = undefined;
    const backend = createScreeningBackend({ serviceKey: 'test-only', fetcher: async () => new Response('true') });
    if (await backend.rpc('claim_screening_run') !== true) throw Error('RPC failed');
    const child = createPhotoPreparationHandler({ enabled: true,
      workerTokenSha256: photoDigest(token), backend, normalize: async () => ({bytes: jpeg, mime:'image/jpeg'}) });
    const denied = await child(new Request('https://example.invalid'));
    if (denied.status !== 401) throw Error('Child authorization failed');
    const prepare = createRemotePhotoPreparer({ gatewayKey: 'test-only', workerToken: token,
      fetcher: async () => new Response(jpeg, {headers: { 'content-type':'image/jpeg',
        'x-heiro-photo-ticket': id, 'x-heiro-photo-revision': revision, 'x-heiro-photo-sha256':photoDigest(jpeg) }}) });
    const result = await prepare({id, lease_token:id, revision},0);
    if (result.bytes.length !== jpeg.length || result.bytes.some((v:number,i:number)=>v!==jpeg[i])) throw Error('Image failed');
  } finally { globals.Buffer = previous; }
});
