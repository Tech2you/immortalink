import { createHash, timingSafeEqual } from 'node:crypto';
import { processScreeningPhoto, validPhotoWork, validPreparedPhoto, PHOTO_RESPONSE_BYTES } from './photo_job.mjs';

const endpoint = 'https://vbzyvaylfdhwowdbodmk.supabase.co/functions/v1/prepare_screening_photo';
const failure = () => new Error('PHOTO_TRANSPORT_UNAVAILABLE');
const headers = { 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' };
const json = (status, code) => Response.json({ code }, { status, headers });

async function readBytes(message, max, signal) {
  const length = message.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > max)) {
    void message.body?.cancel().catch(() => {}); throw failure();
  }
  const reader = message.body?.getReader();
  if (!reader) throw failure();
  const chunks = []; let size = 0;
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, { once: true });
  try {
    for (;;) {
      if (signal.aborted) throw failure();
      const { done, value } = await reader.read();
      if (signal.aborted) throw failure();
      if (done) break;
      size += value.length;
      if (size > max) { abort(); throw failure(); }
      chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks, size);
  } finally {
    signal.removeEventListener('abort', abort); reader.releaseLock();
    for (const part of chunks) part.fill(0);
  }
}

// Factory only, not deployed. Production must also keep gateway JWT validation.
// A separate random worker secret authorizes internal requests, never app JWTs.
export function createPhotoPreparationHandler({ enabled = false, workerTokenSha256, backend, normalize } = {}) {
  const pin = typeof workerTokenSha256 === 'string' && /^[a-f0-9]{64}$/.test(workerTokenSha256)
    ? Buffer.from(workerTokenSha256, 'hex') : null;
  let busy = false;
  return async request => {
    if (enabled !== true || !pin || !backend || typeof normalize !== 'function') return json(503, 'SCREENING_DISABLED');
    const token = request.headers.get('x-heiro-screening-worker') || '';
    if (token.length < 32 || token.length > 256 ||
        !timingSafeEqual(createHash('sha256').update(token).digest(), pin)) return json(401, 'UNAUTHORIZED');
    if (request.method !== 'POST') return json(405, 'METHOD_NOT_ALLOWED');
    if (request.headers.get('content-type') !== 'application/json') return json(400, 'INVALID_WORK');
    if (busy) return json(429, 'WORKER_BUSY');
    busy = true;
    let body, image;
    try {
      body = await readBytes(request, 1024, AbortSignal.timeout(5000));
      const work = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(body));
      if (!validPhotoWork(work)) return json(400, 'INVALID_WORK');
      image = await processScreeningPhoto({ enabled, backend, normalize, work });
      if (image.state !== 'ready') return json(503, 'PHOTO_NOT_READY');
      // Response copies the bounded bytes; clear the worker-owned original below.
      return new Response(image.bytes, { headers: { ...headers, 'content-type': 'image/jpeg',
        'x-heiro-photo-ticket': image.ticket_id, 'x-heiro-photo-sha256': image.sha256,
        'x-heiro-photo-revision': work.job.revision } });
    } catch { return json(503, 'PHOTO_NOT_READY'); }
    finally { body?.fill(0); image?.bytes?.fill(0); busy = false; }
  };
}

// One fixed internal HTTP request per image. No retries or arbitrary URLs.
export function createRemotePhotoPreparer({ gatewayKey, workerToken, fetcher = fetch, timeoutMs = 20000 } = {}) {
  if (typeof gatewayKey !== 'string' || !gatewayKey.trim() || typeof workerToken !== 'string' ||
      !/^[A-Za-z0-9_-]{32,256}$/.test(workerToken) || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 20000) throw failure();
  return async (job, index) => {
    const work = { job, image_index: index };
    if (!validPhotoWork(work)) throw failure();
    const controller = new AbortController(); let timer;
    const deadline = new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(failure()); }, timeoutMs); });
    try {
      return await Promise.race([deadline, (async () => {
        const response = await fetcher(endpoint, { method: 'POST', redirect: 'error', cache: 'no-store',
          signal: controller.signal, headers: { Authorization: `Bearer ${gatewayKey}`,
            'x-heiro-screening-worker': workerToken, 'content-type': 'application/json' }, body: JSON.stringify(work) });
        if (!response.ok || response.headers.get('content-type') !== 'image/jpeg' ||
            response.headers.get('x-heiro-photo-revision') !== job.revision) {
          void response.body?.cancel().catch(() => {}); throw failure();
        }
        const bytes = await readBytes(response, PHOTO_RESPONSE_BYTES, controller.signal);
        const image = { bytes, mime: 'image/jpeg', ticket_id: response.headers.get('x-heiro-photo-ticket'),
          sha256: response.headers.get('x-heiro-photo-sha256') };
        if (!validPreparedPhoto(image)) { bytes.fill(0); throw failure(); }
        return image;
      })()]);
    } catch { throw failure(); }
    finally { clearTimeout(timer); controller.abort(); }
  };
}
