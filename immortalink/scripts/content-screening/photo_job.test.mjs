import { test } from 'node:test';
import assert from 'node:assert/strict';
import { processScreeningPhoto, validPhotoWork, photoDigest } from './photo_job.mjs';

const id = '11111111-1111-4111-8111-111111111111';
const revision = 'a'.repeat(64);
const work = { job: { id, lease_token: id, revision }, image_index: 0 };
const jpeg = () => Uint8Array.from([255, 216, 255, 224, 1, 2, 255, 217]);
function fixture() {
  const calls = [], input = jpeg(), output = jpeg();
  const claim = { code: 'PHOTO_CLAIMED', processing_reserved: true, revision, image_index: 0,
    ticket_id: id, image: { id, bucket: 'memory_photos', path: 'family/vault/photo.jpg',
      updated_at: '2026-10-24T00:00:00Z', metadata: { size: input.length, mimetype: 'image/jpeg', eTag: 'a'.repeat(32) } } };
  const completion = { code: 'PHOTO_READY', revision };
  const backend = {
    async rpc(name, args) { calls.push({ name, args }); return name.startsWith('claim_') ? claim : completion; },
    async download() { calls.push({ name: 'download' }); return input; },
  };
  return { input, output, claim, completion, calls,
    options: { enabled: true, backend, work, normalize: async () => ({ bytes: output, mime: 'image/jpeg' }) } };
}

test('photo preparation is default-off and rejects extra fields, URLs and invalid ordinals before claiming', async () => {
  const f = fixture();
  for (const enabled of [undefined, false, 'true', 1]) {
    assert.equal((await processScreeningPhoto({ ...f.options, enabled })).code, 'SCREENING_DISABLED');
  }
  for (const bad of [null, { ...work, url: 'https://example.com' }, { ...work, image_index: 4 },
    { ...work, image_index: -1 }, { ...work, image_index: '0' }, { ...work, job: { ...work.job, url: 'private' } },
    { ...work, job: { ...work.job, revision: '' } }]) {
    assert(!validPhotoWork(bad));
    assert.equal((await processScreeningPhoto({ ...f.options, work: bad })).code, 'PHOTO_WORK_INVALID');
  }
  assert.deepEqual(f.calls, []);
});

test('one photo is claimed, normalized and confirmed without retaining the originals', async () => {
  const f = fixture(), expected = jpeg();
  const result = await processScreeningPhoto(f.options);
  assert.equal(result.state, 'ready'); assert.deepEqual(result.bytes, expected);
  assert.equal(result.sha256, photoDigest(expected));
  assert.deepEqual(f.calls.map(c => c.name), ['claim_content_screening_photo', 'download', 'finish_content_screening_photo']);
  assert.deepEqual(f.calls.at(-1).args, { p_ticket: id, p_bytes: expected.length, p_sha256: photoDigest(expected) });
  assert(f.input.every(x => x === 0)); assert(f.output.every(x => x === 0));
  result.bytes.fill(0);
});

test('unclaimed, replayed, wrong-source or unbudgeted work cannot download a photo', async () => {
  for (const patch of [{ code: 'PHOTO_ALREADY_CLAIMED' }, { processing_reserved: false },
    { revision: 'b'.repeat(64) }, { image_index: 1 }, { ticket_id: 'bad' }, { image: {} }]) {
    const f = fixture(); Object.assign(f.claim, patch);
    assert.equal((await processScreeningPhoto(f.options)).state, 'pending');
    assert.deepEqual(f.calls.map(c => c.name), ['claim_content_screening_photo']);
  }
});

test('withdrawal or changed source after decode emits no bytes and does not retry', async () => {
  for (const patch of [{ code: 'SOURCE_CHANGED' }, { revision: 'b'.repeat(64) }]) {
    const f = fixture(); Object.assign(f.completion, patch);
    const result = await processScreeningPhoto(f.options);
    assert.deepEqual(result, { state: 'pending', code: 'PHOTO_NOT_CONFIRMED' });
    assert.equal(f.calls.length, 3);
    assert(f.input.every(x => x === 0)); assert(f.output.every(x => x === 0));
  }
});

test('corrupt, oversized or wrong-format normalization cannot finish; source bytes are cleared', async () => {
  for (const output of [{ bytes: new Uint8Array(10), mime: 'image/jpeg' },
    { bytes: new Uint8Array(2097153), mime: 'image/jpeg' }, { bytes: jpeg(), mime: 'image/png' }]) {
    const f = fixture();
    const result = await processScreeningPhoto({ ...f.options, normalize: async () => output });
    assert.equal(result.code, 'PHOTO_INVALID');
    assert.equal(f.calls.length, 2); assert(f.input.every(x => x === 0));
    assert(output.bytes.every(x => x === 0));
  }
});

test('normalizer aliases do not erase transferred output; thrown errors do not leak diagnostics', async () => {
  const f = fixture();
  const result = await processScreeningPhoto({ ...f.options, normalize: async input => ({ bytes: input, mime: 'image/jpeg' }) });
  assert.deepEqual(result.bytes, jpeg()); assert(f.input.every(x => x === 0)); result.bytes.fill(0);
  const broken = fixture();
  assert.deepEqual(await processScreeningPhoto({ ...broken.options, normalize: async () => { throw new Error('PRIVATE'); } }),
    { state: 'pending', code: 'PHOTO_UNAVAILABLE' });
  assert(broken.input.every(x => x === 0)); assert.equal(broken.calls.length, 2);
});
