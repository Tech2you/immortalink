import { createHash } from 'node:crypto';

const origin = 'https://vbzyvaylfdhwowdbodmk.supabase.co';
const rpcNames = new Set(['claim_content_screening', 'prepare_content_screening', 'finish_content_screening',
  'claim_content_screening_photo', 'finish_content_screening_photo']);
const buckets = new Set(['vault_photos', 'memory_photos', 'legacy_memory_photos']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const mimes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const failure = () => new Error('SCREENING_BACKEND_UNAVAILABLE');
export const TRANSFER_LIMITS = Object.freeze({ photoBytes: 12 * 1024 * 1024, jsonBytes: 128 * 1024, timeoutMs: 15000 });

export function checkedObject(item) {
  if (!item || !uuid.test(item.id) || !buckets.has(item.bucket) || typeof item.path !== 'string' ||
      item.path.length > 2048 || /[\\\x00-\x1f\x7f%?#]/.test(item.path) || item.path.split('/').length < 3 ||
      item.path.split('/').some(p => !p || p === '.' || p === '..') ||
      typeof item.updated_at !== 'string' || !Number.isFinite(Date.parse(item.updated_at)) ||
      !mimes.has(item.metadata?.mimetype) || !Number.isSafeInteger(Number(item.metadata?.size)) ||
      Number(item.metadata.size) < 1 || Number(item.metadata.size) > TRANSFER_LIMITS.photoBytes ||
      typeof item.metadata?.eTag !== 'string' || !/^[a-f0-9]{32}$/i.test(item.metadata.eTag)) throw failure();
  return { path: `/storage/v1/object/authenticated/${item.bucket}/${item.path.split('/').map(encodeURIComponent).join('/')}`,
    bytes: Number(item.metadata.size), mime: item.metadata.mimetype, digest: item.metadata.eTag.toLowerCase() };
}

async function bounded(response, maximum) {
  if (!response.ok || !response.body) { void response.body?.cancel().catch(() => {}); throw failure(); }
  const declared = response.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > maximum)) {
    void response.body.cancel().catch(() => {}); throw failure();
  }
  const reader = response.body.getReader();
  const chunks = []; let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximum) { void reader.cancel().catch(() => {}); throw failure(); }
      chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks, size);
  } finally { reader.releaseLock(); }
}

// No credential discovery or automatic polling. Only explicit server credentials,
// a fixed project, a closed RPC set and source references from a current lease.
export function createScreeningBackend({ serviceKey, fetcher = fetch }) {
  if (typeof serviceKey !== 'string' || !serviceKey.trim()) throw failure();
  async function send(path, body, max, extraHeaders = {}) {
    const controller = new AbortController(); let timer;
    const deadline = new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(failure()); }, TRANSFER_LIMITS.timeoutMs); });
    try {
      return await Promise.race([deadline, (async () => {
        const response = await fetcher(origin + path, { method: body === undefined ? 'GET' : 'POST',
          redirect: 'error', cache: 'no-store', signal: controller.signal,
          headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json', ...extraHeaders },
          body: body === undefined ? undefined : JSON.stringify(body) });
        return { bytes: await bounded(response, max), headers: response.headers };
      })()]);
    } catch { throw failure(); }
    finally { clearTimeout(timer); controller.abort(); }
  }
  return {
    async rpc(name, args = {}) {
      if (!rpcNames.has(name)) throw failure();
      const { bytes } = await send(`/rest/v1/rpc/${name}`, args, TRANSFER_LIMITS.jsonBytes);
      try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
      catch { throw failure(); }
      finally { bytes.fill(0); }
    },
    async download(item) {
      const object = checkedObject(item);
      const { bytes, headers } = await send(object.path, undefined, object.bytes, { 'If-Match': `"${object.digest}"` });
      const etag = headers.get('etag');
      const type = headers.get('content-type')?.split(';')[0].trim();
      // MD5 is the Storage ETag coherency check, not an authenticity signature.
      // Source/consent is also rechecked against the DB before dispatch and finish.
      if (bytes.length !== object.bytes || etag !== `"${object.digest}"` || type !== object.mime ||
          createHash('md5').update(bytes).digest('hex') !== object.digest) {
        bytes.fill(0); throw failure();
      }
      return bytes;
    },
  };
}
