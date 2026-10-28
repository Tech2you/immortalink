import { createHash } from 'node:crypto';
import { checkedObject } from './backend.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hash = /^[a-f0-9]{64}$/;
export const PHOTO_RESPONSE_BYTES = 2 * 1024 * 1024;
export const photoDigest = bytes => createHash('sha256').update(bytes).digest('hex');
export function validPhotoWork(work) {
  const job = work?.job;
  return work && typeof work === 'object' && !Array.isArray(work) &&
    Object.keys(work).every(k => ['job', 'image_index'].includes(k)) &&
    job && typeof job === 'object' && !Array.isArray(job) &&
    Object.keys(job).every(k => ['id', 'lease_token', 'revision'].includes(k)) &&
    uuid.test(job.id) && uuid.test(job.lease_token) && hash.test(job.revision) &&
    Number.isInteger(work.image_index) && work.image_index >= 0 && work.image_index < 4;
}
export function validPreparedPhoto(image) {
  return image?.bytes instanceof Uint8Array && image.bytes.length > 3 &&
    image.bytes.length <= PHOTO_RESPONSE_BYTES && image.mime === 'image/jpeg' &&
    image.bytes[0] === 255 && image.bytes[1] === 216 && image.bytes[2] === 255 &&
    uuid.test(image.ticket_id) && hash.test(image.sha256) && photoDigest(image.bytes) === image.sha256;
}

// Exactly one source/decode per call, no provider or durable image storage.
// A failed/ambiguous call consumes its ticket; only a new metered parent lease
// can retry. Consent and deletion are checked before download and after decode.
export async function processScreeningPhoto({ enabled = false, backend, normalize, work } = {}) {
  if (enabled !== true) return { state: 'pending', code: 'SCREENING_DISABLED' };
  if (!backend || typeof normalize !== 'function' || !validPhotoWork(work)) {
    return { state: 'pending', code: 'PHOTO_WORK_INVALID' };
  }
  let output, transferred = false;
  try {
    const { job, image_index: index } = work;
    const claim = await backend.rpc('claim_content_screening_photo', {
      p_job: job.id, p_lease: job.lease_token, p_index: index,
    });
    if (claim?.code !== 'PHOTO_CLAIMED' || claim.processing_reserved !== true ||
        claim.revision !== job.revision || claim.image_index !== index || !uuid.test(claim.ticket_id)) {
      return { state: 'pending', code: 'PHOTO_NOT_CLAIMED' };
    }
    checkedObject(claim.image);
    const bytes = await backend.download(claim.image);
    let image;
    try {
      image = await normalize(bytes, claim.image.metadata.mimetype);
      if (!(image?.bytes instanceof Uint8Array) || !image.bytes.length ||
          image.bytes.length > PHOTO_RESPONSE_BYTES || image.mime !== 'image/jpeg') {
        return { state: 'pending', code: 'PHOTO_INVALID' };
      }
      output = new Uint8Array(image.bytes);
    } finally { bytes.fill(0); if (image?.bytes instanceof Uint8Array) image.bytes.fill(0); }
    const result = { bytes: output, mime: 'image/jpeg', ticket_id: claim.ticket_id, sha256: photoDigest(output) };
    if (!validPreparedPhoto(result)) return { state: 'pending', code: 'PHOTO_INVALID' };
    const completed = await backend.rpc('finish_content_screening_photo', {
      p_ticket: claim.ticket_id, p_bytes: output.length, p_sha256: result.sha256,
    });
    if (completed?.code !== 'PHOTO_READY' || completed.revision !== job.revision) {
      return { state: 'pending', code: 'PHOTO_NOT_CONFIRMED' };
    }
    transferred = true;
    return { state: 'ready', ...result };
  } catch { return { state: 'pending', code: 'PHOTO_UNAVAILABLE' }; }
  finally { if (!transferred) output?.fill(0); }
}
