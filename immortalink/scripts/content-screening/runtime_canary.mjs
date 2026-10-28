import { createHash, timingSafeEqual } from 'node:crypto';
import { Buffer } from 'node:buffer';

const reply = (status, body) => Response.json(body, { status, headers: { 'cache-control': 'no-store' } });
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

async function boundedBytes(response, limit, signal, onFirstChunk = () => {}) {
  const chunks = []; let total = 0;
  const reader = response.body?.getReader();
  if (!reader) throw new Error('EMPTY_BODY');
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, { once: true });
  try {
    for (;;) {
      if (signal.aborted) throw new Error('DEADLINE');
      const { done, value } = await reader.read();
      if (signal.aborted) throw new Error('DEADLINE');
      if (done) break;
      if (total === 0) onFirstChunk();
      total += value.byteLength;
      if (total > limit) { abort(); throw new Error('BODY_LIMIT'); }
      chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks, total);
  } finally {
    signal.removeEventListener('abort', abort); reader.releaseLock();
    for (const bytes of chunks) bytes.fill(0);
  }
}

// Diagnostics only. Observers receive fixed stage names, never request data.
// No database, Storage client, AI request or file write.
// Public app tokens cannot call this handler, even if the gateway accepts them.
export function createRuntimeCanary({ serviceKeySha256, expiresAt, fixtures, loadNormalizer, now = Date.now, onStage = () => {} }) {
  if (typeof serviceKeySha256 !== 'string' || !/^[a-f0-9]{64}$/.test(serviceKeySha256) || !Number.isFinite(expiresAt) ||
      !fixtures || Object.keys(fixtures).length !== 3 || typeof loadNormalizer !== 'function' ||
      typeof onStage !== 'function') throw new Error('INVALID_CANARY_CONFIG');
  const mark = stage => { try { onStage(stage); } catch {} };
  for (const [name, f] of Object.entries(fixtures)) {
    if (!/^[a-z0-9_-]{1,30}$/.test(name) || !/^[a-f0-9]{64}$/.test(f.sha256) ||
        !Number.isSafeInteger(f.bytes) || f.bytes < 1 || f.bytes > 12 * 1024 * 1024 ||
        !Number.isInteger(f.count) || f.count < 1 || f.count > 4 || f.bytes * f.count > 24 * 1024 * 1024) throw new Error('INVALID_CANARY_CONFIG');
  }
  const expected = Buffer.from(serviceKeySha256, 'hex'), used = new Set(); let busy = false;
  return async request => {
    mark('request_received');
    // Gateway auth remains enabled. This independent header binds diagnostics
    // to the exact approved operator key without assuming injected keys match it.
    const supplied = Buffer.from(request.headers.get('x-heiro-canary-key') || '');
    if (supplied.length < 16 || supplied.length > 8192 ||
        !timingSafeEqual(createHash('sha256').update(supplied).digest(), expected)) return reply(401, { code: 'UNAUTHORIZED' });
    mark('authorized');
    if (request.method !== 'POST') return reply(405, { code: 'METHOD_NOT_ALLOWED' });
    if (now() >= expiresAt) return reply(410, { code: 'CANARY_EXPIRED' });
    const name = new URL(request.url).searchParams.get('fixture');
    const fixture = Object.hasOwn(fixtures, name ?? '') ? fixtures[name] : null;
    if (!fixture || request.headers.get('content-type') !== 'application/octet-stream') return reply(400, { code: 'INVALID_FIXTURE' });
    const declared = request.headers.get('content-length');
    if (declared !== null && declared !== String(fixture.bytes)) return reply(413, { code: 'BODY_LIMIT' });
    if (busy || used.has(name)) return reply(429, { code: 'CANARY_LIMIT' });
    busy = true; const outputs = []; let source;
    try {
      mark('body_started');
      source = await boundedBytes(request, fixture.bytes, AbortSignal.timeout(15000), () => mark('body_first_chunk'));
      mark('body_ready');
      if (source.length !== fixture.bytes || sha256(source) !== fixture.sha256) return reply(400, { code: 'FIXTURE_MISMATCH' });
      if (now() >= expiresAt) return reply(410, { code: 'CANARY_EXPIRED' });
      used.add(name);
      mark('fixture_verified');
      const start = performance.now(), normalize = await loadNormalizer();
      mark('normalizer_ready');
      for (let i = 0; i < fixture.count; i++) {
        mark('photo_started');
        const image = await normalize(source, 'image/jpeg');
        if (!(image?.bytes instanceof Uint8Array) || image.mime !== 'image/jpeg' || image.bytes.length > 2 * 1024 * 1024) throw new Error('INVALID_OUTPUT');
        outputs.push(image.bytes);
        mark('photo_ready');
      }
      // Include retaining all outputs and serializing the eventual batch, but
      // never send it anywhere or return its content in the diagnostic response.
      const payload = JSON.stringify({ input: outputs.map(bytes => ({ type: 'image_url',
        image_url: { url: `data:image/jpeg;base64,${Buffer.from(bytes).toString('base64')}` } })) });
      if (Buffer.byteLength(payload) > 15 * 1024 * 1024) throw new Error('OUTPUT_LIMIT');
      mark('serialized');
      return reply(200, { fixture: name, completed: outputs.length, outputBytes: outputs.reduce((n, b) => n + b.length, 0),
        serializedBytes: Buffer.byteLength(payload), wallMs: Math.round(performance.now() - start) });
    } catch { mark('failed'); return reply(503, { code: 'CANARY_FAILED' }); }
    finally { source?.fill(0); for (const bytes of outputs) bytes.fill(0); busy = false; }
  };
}

// API bundling cannot include static WASM assets. This diagnostic-only loader
// fetches one exact, public pinned binary, verifying its hash before execution.
// It is NOT the selected production packaging or a user-controlled URL fetcher.
export function createCanaryNormalizerLoader({ sha256: digest, bytes: size, createPreparer, fetcher = fetch, onStage = () => {} }) {
  if (!/^[a-f0-9]{64}$/.test(digest) || !Number.isInteger(size) || size <= 0 || size > 20 * 1024 * 1024 ||
      typeof createPreparer !== 'function' || typeof onStage !== 'function') throw new Error('INVALID_BINARY_CONFIG');
  const mark = stage => { try { onStage(stage); } catch {} };
  let pending;
  return () => pending ??= (async () => {
    const signal = AbortSignal.timeout(15000);
    mark('binary_fetch_started');
    const response = await fetcher('https://cdn.jsdelivr.net/npm/@imagemagick/magick-wasm@0.0.45/dist/x86/magick.wasm',
      { redirect: 'error', signal });
    mark('binary_headers_received');
    if (!response.ok) { void response.body?.cancel().catch(() => {}); throw new Error('BINARY_UNAVAILABLE'); }
    const binary = await boundedBytes(response, size, signal, () => mark('binary_first_chunk'));
    try {
      if (binary.length !== size || sha256(binary) !== digest) throw new Error('BINARY_UNAVAILABLE');
      mark('binary_verified');
      mark('wasm_init_started');
      const prepare = await createPreparer(binary);
      mark('wasm_init_ready');
      return prepare;
    } finally { binary.fill(0); }
  })();
}
