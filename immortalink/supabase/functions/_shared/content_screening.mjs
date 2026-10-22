// Provider adapter only. This module neither publishes content nor authorizes
// access. A server-side queue must verify consent, ownership, revision and budget
// before calling it. Keep it disconnected until publication enforcement is ready.
export const SCREENING_LIMITS = Object.freeze({
  textCharacters: 20000,
  imageBytes: 10 * 1024 * 1024,
  responseBytes: 32 * 1024,
  timeoutMs: 15000,
});

export const SCREENING_CATEGORIES = Object.freeze([
  'harassment', 'harassment/threatening', 'hate', 'hate/threatening',
  'illicit', 'illicit/violent', 'self-harm', 'self-harm/intent',
  'self-harm/instructions', 'sexual', 'sexual/minors', 'violence',
  'violence/graphic',
]);

const endpoint = 'https://api.openai.com/v1/moderations';
const model = 'omni-moderation-latest';
const pending = (code) => ({ state: 'pending', code, categories: [] });
const isRecord = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function imageMime(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if ([137, 80, 78, 71, 13, 10, 26, 10].every((b, i) => bytes[i] === b)) return 'image/png';
  if ([82, 73, 70, 70].every((b, i) => bytes[i] === b) &&
      [87, 69, 66, 80].every((b, i) => bytes[i + 8] === b)) return 'image/webp';
  return null;
}

function encodeImage(bytes) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(binary);
}

function buildInput(content) {
  if (!isRecord(content) || Object.keys(content).some((key) => !['text', 'image'].includes(key))) {
    return { error: 'INPUT_UNSUPPORTED' };
  }
  const { text = '', image } = content;
  if (typeof text !== 'string') return { error: 'TEXT_INVALID' };
  if (text.length > SCREENING_LIMITS.textCharacters) return { error: 'TEXT_TOO_LARGE' };
  const input = [];
  if (text.trim()) input.push({ type: 'text', text });
  if (image !== undefined) {
    if (!isRecord(image) || Object.keys(image).some((key) => !['bytes', 'mime'].includes(key)) ||
        !(image.bytes instanceof Uint8Array)) return { error: 'IMAGE_INVALID' };
    if (!image.bytes.length || image.bytes.length > SCREENING_LIMITS.imageBytes) {
      return { error: 'IMAGE_SIZE_INVALID' };
    }
    const mime = imageMime(image.bytes);
    if (!mime || mime !== image.mime) return { error: 'IMAGE_FORMAT_UNSUPPORTED' };
    // Only inline, server-loaded bytes are accepted. Never fetch client URLs or
    // expose storage signed URLs, family IDs or filenames to the provider.
    input.push({ type: 'image_url', image_url: { url: `data:${mime};base64,${encodeImage(image.bytes)}` } });
  }
  return input.length ? { input } : { error: 'INPUT_EMPTY' };
}

export function interpretScreeningResponse(body) {
  if (!isRecord(body) || !Array.isArray(body.results) || body.results.length !== 1) {
    return pending('PROVIDER_RESPONSE_INVALID');
  }
  const result = body.results[0];
  if (!isRecord(result) || typeof result.flagged !== 'boolean' ||
      !isRecord(result.categories) || !isRecord(result.category_scores)) {
    return pending('PROVIDER_RESPONSE_INVALID');
  }
  const categories = result.categories;
  const scores = result.category_scores;
  if (SCREENING_CATEGORIES.some((category) => !Object.hasOwn(categories, category)) ||
      Object.values(categories).some((value) => typeof value !== 'boolean') ||
      Object.keys(categories).some((category) => !Object.hasOwn(scores, category) ||
        typeof scores[category] !== 'number' || !Number.isFinite(scores[category]) ||
        scores[category] < 0 || scores[category] > 1)) {
    return pending('PROVIDER_RESPONSE_INVALID');
  }
  const flagged = result.flagged || Object.values(categories).some(Boolean);
  return {
    state: flagged ? 'review' : 'clear',
    code: flagged ? 'HUMAN_REVIEW_REQUIRED' : 'SCREENING_CLEAR',
    // Only known category names leave the adapter, never arbitrary provider text.
    categories: SCREENING_CATEGORIES.filter((category) => categories[category]),
  };
}

async function readBoundedJson(response) {
  if (!response.body) throw new Error('EMPTY_RESPONSE');
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > SCREENING_LIMITS.responseBytes) {
        await reader.cancel();
        throw new Error('RESPONSE_TOO_LARGE');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

/**
 * Performs ONE text/photo screening request, with no automatic retries.
 * `clear` is a provider finding, not permission to publish. The caller must
 * atomically recheck the claimed revision, deletion, restrictions and consent.
 * Audio and known/suspected CSAM must not be passed to this adapter.
 */
export async function screenTextOrImage(content, {
  enabled = false,
  apiKey,
  fetcher = fetch,
} = {}) {
  if (enabled !== true) return pending('SCREENING_DISABLED');
  if (typeof apiKey !== 'string' || !apiKey.trim()) return pending('PROVIDER_NOT_CONFIGURED');
  const prepared = buildInput(content);
  if (prepared.error) return pending(prepared.error);

  const controller = new AbortController();
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve(pending('PROVIDER_UNAVAILABLE'));
    }, SCREENING_LIMITS.timeoutMs);
  });
  const request = (async () => {
    try {
      const response = await fetcher(endpoint, {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ model, input: prepared.input }),
        signal: controller.signal,
        redirect: 'error',
      });
      if (!response.ok) {
        await response.body?.cancel();
        return pending(response.status === 429 ? 'PROVIDER_RATE_LIMITED' : 'PROVIDER_UNAVAILABLE');
      }
      return interpretScreeningResponse(await readBoundedJson(response));
    } catch {
      // Error bodies can echo private text or keys. Return only a fixed code.
      return pending('PROVIDER_UNAVAILABLE');
    }
  })();
  try { return await Promise.race([request, timeout]); }
  finally { clearTimeout(timer); }
}
