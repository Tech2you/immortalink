import { screenTextOrImage, SCREENING_LIMITS } from '../../supabase/functions/_shared/content_screening.mjs';
import { checkedObject } from './backend.mjs';
import { validPreparedPhoto, photoDigest } from './photo_job.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const revision = /^[a-f0-9]{64}$/;
const pending = code => ({ state: 'pending', code });

// One lease per call, no scheduler, no client route, no publication side effect.
// The owner has not approved activation. There is deliberately no runnable CLI.
export async function processScreeningJob({ enabled = false, backend, apiKey,
  fetcher = fetch, normalize, prepareImage } = {}) {
  if (enabled !== true) return pending('SCREENING_DISABLED');
  const split = typeof prepareImage === 'function';
  if (!backend || typeof apiKey !== 'string' || !apiKey.trim() ||
      (!split && typeof normalize !== 'function') || (split && normalize !== undefined)) return pending('WORKER_NOT_CONFIGURED');
  let job; const images = [], proofs = [];
  try {
    job = await backend.rpc('claim_content_screening');
    if (job === null) return { state: 'idle', code: 'NO_WORK' };
    if (!job || !uuid.test(job.id) || !uuid.test(job.lease_token) || !revision.test(job.revision)) return pending('CLAIM_INVALID');
    const lease = { p_job: job.id, p_lease: job.lease_token };
    const source = await backend.rpc('prepare_content_screening', { ...lease, p_authorize: false });
    if (source?.code !== 'READY' || source.revision !== job.revision || source.processing_reserved !== true) return pending('SOURCE_UNAVAILABLE');
    if (typeof source.text !== 'string' || new TextEncoder().encode(source.text).length > 20000 ||
        !Array.isArray(source.images) || source.images.length > SCREENING_LIMITS.images ||
        (!source.text.trim() && source.images.length === 0)) return pending('SOURCE_INVALID');
    // Validate every reference before any download; process sequentially so only
    // one original compressed image is retained at a time.
    const refs = new Set(); let sourceBytes = 0;
    for (const item of source.images) {
      const object = checkedObject(item); const ref = object.path;
      sourceBytes += object.bytes;
      if (sourceBytes > 24 * 1024 * 1024) return pending('SOURCE_BATCH_TOO_LARGE');
      if (refs.has(ref)) return pending('SOURCE_INVALID');
      refs.add(ref);
    }
    for (const [index, item] of source.images.entries()) {
      // Do not continue loading more family files after a consent/source change.
      const current = await backend.rpc('prepare_content_screening', { ...lease, p_authorize: false });
      if (current?.code !== 'READY' || current.revision !== job.revision || current.processing_reserved !== true) return pending('SOURCE_UNAVAILABLE');
      if (split) {
        // Send only the lease and ordinal, never client-selected bytes or URLs.
        const image = await prepareImage(job, index);
        if (!validPreparedPhoto(image)) {
          if (image?.bytes instanceof Uint8Array) image.bytes.fill(0);
          return pending('PHOTO_INVALID');
        }
        proofs.push({ ticket_id: image.ticket_id, sha256: image.sha256 });
        images.push({ bytes: image.bytes, mime: image.mime });
        continue;
      }
      const bytes = await backend.download(item);
      try {
        const image = await normalize(bytes, item.metadata.mimetype);
        if (!(image?.bytes instanceof Uint8Array) || image.mime !== 'image/jpeg' ||
            !image.bytes.length || image.bytes.length > 2 * 1024 * 1024) {
          if (image?.bytes instanceof Uint8Array) image.bytes.fill(0);
          return pending('PHOTO_INVALID');
        }
        images.push(image);
      } finally { bytes.fill(0); }
    }
    if (split) {
      const current = await backend.rpc('prepare_content_screening', { ...lease, p_authorize: false });
      if (current?.code !== 'READY' || current.revision !== job.revision || current.processing_reserved !== true ||
          !Array.isArray(current.prepared_images) || current.prepared_images.length !== images.length) return pending('PHOTO_MANIFEST_UNAVAILABLE');
      for (const [index, image] of images.entries()) {
        const proof = current.prepared_images[index];
        if (proof?.image_index !== index || proof.ticket_id !== proofs[index].ticket_id ||
            proof.bytes !== image.bytes.length || proof.sha256 !== proofs[index].sha256 ||
            proof.sha256 !== photoDigest(image.bytes)) return pending('PHOTO_MANIFEST_MISMATCH');
      }
    }
    const authorized = await backend.rpc('prepare_content_screening', { ...lease, p_authorize: true });
    if (authorized?.code !== 'DISPATCH_RESERVED' || authorized.revision !== job.revision) return pending('DISPATCH_NOT_AUTHORIZED');
    const result = await screenTextOrImage({ text: source.text, images }, { enabled: true, apiKey, fetcher });
    const completed = await backend.rpc('finish_content_screening', { ...lease, p_outcome: result.state });
    // Only the DB's rechecked completion is returned. A provider clear cannot
    // survive a declined/expired lease, changed revision or failed commit.
    if (!completed || !['clear', 'review', 'queued', 'stale'].includes(completed.state)) return pending('COMPLETION_UNCONFIRMED');
    return { state: completed.state, code: ({ clear: 'REVISION_CLEAR', review: 'HUMAN_REVIEW_REQUIRED',
      queued: 'RETRY_QUEUED', stale: 'SOURCE_CHANGED' })[completed.state] };
  } catch {
    // Before authorization the lease expires for bounded retry. After an
    // ambiguous dispatch/commit never retry here or log source/error payloads.
    return pending('WORKER_UNAVAILABLE');
  } finally { for (const image of images) image.bytes.fill(0); }
}
