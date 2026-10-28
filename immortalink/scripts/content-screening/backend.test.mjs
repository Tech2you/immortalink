import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { checkedObject, createScreeningBackend, TRANSFER_LIMITS } from './backend.mjs';

const data = Buffer.from('synthetic transport fixture');
const digest = createHash('md5').update(data).digest('hex');
const item = () => ({ id: '11111111-1111-4111-8111-111111111111', bucket: 'memory_photos', path: 'family/vault/test file.png',
  updated_at: '2026-10-23T10:00:00Z', metadata: { eTag: digest, mimetype: 'image/png', size: data.length } });
const response = (body = data, overrides = {}) => new Response(body, { headers: { etag: `"${digest}"`,
  'content-type': 'image/png', 'content-length': String(data.length), ...overrides } });
const backend = fetcher => createScreeningBackend({ serviceKey: 'test-service-key', fetcher });

test('fixed private Storage endpoint checks version, size, MIME and digest without exposing URLs', async () => {
  let calls = 0;
  const client = backend(async (url, options) => {
    calls++;
    assert.equal(url, 'https://vbzyvaylfdhwowdbodmk.supabase.co/storage/v1/object/authenticated/memory_photos/family/vault/test%20file.png');
    assert.equal(options.method, 'GET'); assert.equal(options.redirect, 'error'); assert.equal(options.cache, 'no-store');
    assert.equal(options.headers['If-Match'], `"${digest}"`); assert.equal(options.headers.Authorization, 'Bearer test-service-key');
    return response();
  });
  assert.deepEqual(await client.download(item()), data); assert.equal(calls, 1);
});

test('path tricks, unsupported buckets and missing server version metadata never fetch', async () => {
  for (const change of [
    { path: '../vault/image.png' }, { path: 'family/../image.png' }, { path: 'family//image.png' },
    { path: 'family/vault/%2e%2e' }, { path: 'family/vault/x?token=secret' }, { path: 'family\\vault/x' },
    { path: 'https://attacker.invalid/image.png' }, { bucket: 'avatars' }, { id: 'bad' },
    { updated_at: null }, { metadata: { size: 1, mimetype: 'image/png' } },
    { metadata: { size: 1, mimetype: 'video/mp4', eTag: digest } },
    { metadata: { size: TRANSFER_LIMITS.photoBytes + 1, mimetype: 'image/png', eTag: digest } },
  ]) {
    const client = backend(async () => assert.fail('No download allowed'));
    assert.throws(() => checkedObject({ ...item(), ...change }));
    await assert.rejects(client.download({ ...item(), ...change }), { message: 'SCREENING_BACKEND_UNAVAILABLE' });
  }
});

test('mismatched bytes, MIME, ETag, weak validators and HTTP failures never return media', async () => {
  for (const make of [
    () => response(Buffer.alloc(data.length)), () => response(data.subarray(1)),
    () => response(data, { etag: '"different"' }), () => response(data, { etag: `W/"${digest}"` }),
    () => response(data, { 'content-type': 'text/html' }),
    () => response(data, { 'content-length': String(data.length + 1) }),
    () => new Response('private upstream error', { status: 412 }),
    () => new Response(null, { status: 302, headers: { location: 'https://attacker.invalid' } }),
  ]) await assert.rejects(backend(async () => make()).download(item()), { message: 'SCREENING_BACKEND_UNAVAILABLE' });
});

test('stream limit ignores lying Content-Length and cancels overflow', async () => {
  let cancelled = false;
  const stream = new ReadableStream({ pull(c) { c.enqueue(new Uint8Array(500)); }, cancel() { cancelled = true; } });
  await assert.rejects(backend(async () => response(stream, { 'content-length': '1' })).download(item()));
  assert.equal(cancelled, true);
});

test('only closed worker RPCs are accepted; malformed JSON and upstream errors stay private', async () => {
  const client = backend(async (url, opts) => {
    assert(url.endsWith('/rest/v1/rpc/claim_content_screening')); assert.equal(opts.method, 'POST');
    return new Response('null');
  });
  assert.equal(await client.rpc('claim_content_screening'), null);
  await assert.rejects(client.rpc('enqueue_content_screening'));
  for (const make of [() => new Response('private invalid JSON'), () => { throw new Error('secret'); }]) {
    await assert.rejects(backend(async () => make()).rpc('claim_content_screening'), { message: 'SCREENING_BACKEND_UNAVAILABLE' });
  }
});

test('deadline covers stalled headers and body without retries', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal; let calls = 0;
  const client = backend(async (_, opts) => { signal = opts.signal; calls++; return new Promise(() => {}); });
  const work = client.download(item()); const rejection = assert.rejects(work, { message: 'SCREENING_BACKEND_UNAVAILABLE' });
  t.mock.timers.tick(TRANSFER_LIMITS.timeoutMs); await rejection;
  assert.equal(signal.aborted, true); assert.equal(calls, 1);
  let controller;
  const body = new ReadableStream({ start(c) { controller = c; } });
  const stalled = backend(async (_, opts) => { signal = opts.signal; return response(body); }).download(item());
  const rejected = assert.rejects(stalled, { message: 'SCREENING_BACKEND_UNAVAILABLE' });
  await Promise.resolve(); t.mock.timers.tick(TRANSFER_LIMITS.timeoutMs); await rejected;
  assert.equal(signal.aborted, true); controller.close();
});
