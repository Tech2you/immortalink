import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPhotoPreparationHandler, createRemotePhotoPreparer } from './photo_transport.mjs';
import { photoDigest } from './photo_job.mjs';

const id = '11111111-1111-4111-8111-111111111111', revision = 'a'.repeat(64);
const job = { id, lease_token: id, revision }, token = 'local-test-only-'.repeat(3);
const jpeg = () => Uint8Array.from([255, 216, 255, 224, 1, 2, 255, 217]);
const headers = () => ({ 'content-type': 'image/jpeg', 'x-heiro-photo-ticket': id,
  'x-heiro-photo-sha256': photoDigest(jpeg()), 'x-heiro-photo-revision': revision });
const options = { gatewayKey: 'local-test-only', workerToken: token };
const request = (body = { job, image_index: 0 }, extra = {}) => new Request('https://example.invalid', {
  method: 'POST', headers: { 'content-type': 'application/json', 'x-heiro-screening-worker': token, ...extra },
  body: JSON.stringify(body),
});
function handlerFixture() {
  let claims = 0, downloads = 0, finishes = 0;
  const original = jpeg(), normalized = jpeg();
  const config = { enabled: true, workerTokenSha256: photoDigest(token),
    normalize: async () => ({ bytes: normalized, mime: 'image/jpeg' }), backend: {
      async rpc(name) {
        if (name.startsWith('finish')) { finishes++; return { code: 'PHOTO_READY', revision }; }
        if (++claims > 1) return { code: 'PHOTO_ALREADY_CLAIMED' };
        return { code: 'PHOTO_CLAIMED', ticket_id: id, processing_reserved: true, revision, image_index: 0,
          image: { id, bucket: 'memory_photos', path: 'family/vault/photo.jpg', updated_at: '2026-10-24T00:00:00Z',
            metadata: { size: original.length, mimetype: 'image/jpeg', eTag: 'a'.repeat(32) } } };
      },
      async download() { downloads++; return original; },
    } };
  return { config, original, normalized, counts: () => ({ claims, downloads, finishes }) };
}

test('internal transport is default-off, requires a separate secret and rejects malformed work before DB access', async () => {
  const f = handlerFixture();
  assert.equal((await createPhotoPreparationHandler({ ...f.config, enabled: false })(request())).status, 503);
  const handler = createPhotoPreparationHandler(f.config);
  for (const secret of ['', 'app-user-jwt', 'x'.repeat(33)]) {
    assert.equal((await handler(request(undefined, { 'x-heiro-screening-worker': secret }))).status, 401);
  }
  assert.equal((await handler(request(undefined, { 'content-type': 'text/plain' }))).status, 400);
  assert.equal((await handler(new Request('https://example.invalid', { headers: { 'x-heiro-screening-worker': token } }))).status, 405);
  for (const body of [{ job, image_index: 4 }, { job, image_index: 0, url: 'https://private' }, { job: {} }]) {
    assert.equal((await handler(request(body))).status, 400);
  }
  assert.equal((await handler(request({ secret: 'x'.repeat(2048) }))).status, 503);
  assert.deepEqual(f.counts(), { claims: 0, downloads: 0, finishes: 0 });
});

test('authenticated child response survives owned-buffer cleanup and replay cannot decode again', async () => {
  const f = handlerFixture(), handler = createPhotoPreparationHandler(f.config);
  const response = await handler(request());
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), jpeg());
  assert(f.original.every(x => x === 0)); assert(f.normalized.every(x => x === 0));
  assert.equal((await handler(request())).status, 503);
  assert.deepEqual(f.counts(), { claims: 2, downloads: 1, finishes: 1 });
});

test('one decoder per handler isolate; a second concurrent request is rejected before claiming', { timeout: 2000 }, async () => {
  const f = handlerFixture(); let release, entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.config.normalize = async () => { entered(); await new Promise(resolve => { release = resolve; }); return { bytes: f.normalized, mime: 'image/jpeg' }; };
  const handler = createPhotoPreparationHandler(f.config), first = handler(request());
  await started;
  assert.equal((await handler(request())).status, 429); assert.equal(f.counts().claims, 1);
  release(); assert.equal((await first).status, 200);
});

test('parent sends one fixed-route request with only the lease and ordinal and validates its proof', async () => {
  let calls = 0;
  const prepare = createRemotePhotoPreparer({ ...options, fetcher: async (url, init) => {
    calls++; assert.equal(url, 'https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/prepare_screening_photo');
    assert.equal(init.redirect, 'error'); assert.equal(init.cache, 'no-store');
    assert.equal(init.headers.Authorization, `Bearer ${options.gatewayKey}`);
    assert.equal(init.headers['x-heiro-screening-worker'], token);
    assert.deepEqual(JSON.parse(init.body), { job, image_index: 0 });
    return new Response(jpeg(), { headers: headers() });
  } });
  const result = await prepare(job, 0); assert.deepEqual(result.bytes, Buffer.from(jpeg())); result.bytes.fill(0);
  await assert.rejects(prepare({ ...job, url: 'https://other' }, 0), /PHOTO_TRANSPORT_UNAVAILABLE/);
  assert.equal(calls, 1);
});

test('non-success responses and tampered metadata never retry or return bytes', async () => {
  for (const change of [h => { h['content-type'] = 'text/plain'; }, h => { h['x-heiro-photo-revision'] = 'b'.repeat(64); },
    h => { h['x-heiro-photo-ticket'] = 'bad'; }, h => { h['x-heiro-photo-sha256'] = 'b'.repeat(64); },
    h => { h['content-length'] = '2097153'; }, h => { h['content-length'] = '-1'; }, null]) {
    let calls = 0;
    const prepare = createRemotePhotoPreparer({ ...options, fetcher: async () => {
      calls++; const h = headers(); change?.(h);
      return new Response(jpeg(), { status: change ? 200 : 503, headers: h });
    } });
    await assert.rejects(prepare(job, 0), /PHOTO_TRANSPORT_UNAVAILABLE/); assert.equal(calls, 1);
  }
});

test('streamed over-limit body is rejected even when declared size lies', async () => {
  let cancelled = false;
  const prepare = createRemotePhotoPreparer({ ...options, fetcher: async () => new Response(new ReadableStream({
    start(c) { c.enqueue(new Uint8Array(2097153)); }, cancel() { cancelled = true; },
  }), { headers: { ...headers(), 'content-length': '8' } }) });
  await assert.rejects(prepare(job, 0), /PHOTO_TRANSPORT_UNAVAILABLE/); assert(cancelled);
});

test('deadline covers both headers and a stalled body, with no retries', async () => {
  for (const stall of ['headers', 'body']) {
    let calls = 0, signal, cancelled = false;
    const prepare = createRemotePhotoPreparer({ ...options, timeoutMs: 15, fetcher: async (_, init) => {
      calls++; signal = init.signal;
      if (stall === 'headers') return new Promise(() => {});
      return new Response(new ReadableStream({ cancel() { cancelled = true; } }), { headers: headers() });
    } });
    await assert.rejects(prepare(job, 0), /PHOTO_TRANSPORT_UNAVAILABLE/);
    assert.equal(calls, 1); assert(signal.aborted);
    if (stall === 'body') assert(cancelled);
  }
});
