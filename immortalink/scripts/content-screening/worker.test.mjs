import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import sharp from 'sharp';
import { processScreeningJob } from './worker.mjs';
import { createScreeningBackend } from './backend.mjs';
import { preparePhoto } from './photo.mjs';
import { createWasmPhotoPreparer } from './photo_wasm.mjs';
import { SCREENING_CATEGORIES } from '../../supabase/functions/_shared/content_screening.mjs';

const id = '11111111-1111-4111-8111-111111111111';
const lease = '22222222-2222-4222-8222-222222222222';
const revision = 'a'.repeat(64);
const photo = await sharp({ create: { width: 20, height: 12, channels: 3, background: '#36924a' } })
  .withExif({ IFD0: { Artist: 'Private metadata test' } }).png().toBuffer();
const safeBody = (flagged = false) => ({ results: [{ flagged,
  categories: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, false])),
  category_scores: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, 0.01])),
}] });
const source = () => ({ code: 'READY', processing_reserved: true, revision, text: 'Family lunch', images: [{ id, bucket: 'memory_photos',
  path: 'family/vault/photo.png', updated_at: '2026-10-23T12:00:00Z',
  metadata: { size: photo.length, mimetype: 'image/png', eTag: createHash('md5').update(photo).digest('hex') } }] });

function mock(overrides = {}) {
  const calls = []; let downloads = 0; let provider = 0;
  const input = source(); const originals = []; const normalized = [];
  const backend = {
    async rpc(name, args) {
      calls.push({ name, args });
      if (overrides.rpc) return overrides.rpc(name, args, input);
      if (name === 'claim_content_screening') return { id, lease_token: lease, revision };
      if (name === 'prepare_content_screening') return args.p_authorize ? { code: 'DISPATCH_RESERVED', revision } : input;
      return { state: 'clear' };
    },
    async download() { downloads++; const bytes = Buffer.from(photo); originals.push(bytes); return bytes; },
  };
  return { calls, input, originals, normalized, counts: () => ({ downloads, provider }),
    options: { enabled: true, apiKey: 'test-only-provider-key', backend,
      normalize: async (...args) => { const result = await preparePhoto(...args); normalized.push(result.bytes); return result; },
      fetcher: async (url, opts) => {
        provider++; assert.equal(url, 'https://api.openai.com/v1/moderations');
        const body = JSON.parse(opts.body);
        assert.deepEqual(Object.keys(body).sort(), ['input', 'model']);
        assert.equal(opts.headers.Authorization, 'Bearer test-only-provider-key');
        assert.equal(opts.body.includes('Private metadata test'), false);
        for (const p of body.input.filter(x => x.type === 'image_url')) {
          const data = Buffer.from(p.image_url.url.split(',')[1], 'base64');
          const meta = await sharp(data).metadata(); assert.equal(meta.exif, undefined); assert.equal(meta.xmp, undefined);
        }
        return new Response(JSON.stringify(safeBody()));
      },
    },
  };
}

test('default-off or unconfigured worker never claims, downloads or sends', async () => {
  const m = mock();
  for (const enabled of [false, undefined, 'true', 1]) {
    assert.equal((await processScreeningJob({ ...m.options, enabled })).code, 'SCREENING_DISABLED');
  }
  assert.equal((await processScreeningJob({ ...m.options, apiKey: '' })).code, 'WORKER_NOT_CONFIGURED');
  assert.equal((await processScreeningJob({ ...m.options, normalize: undefined })).code, 'WORKER_NOT_CONFIGURED');
  assert.deepEqual(m.calls, []); assert.deepEqual(m.counts(), { downloads: 0, provider: 0 });
});

test('one leased memory uses one request after normalization and authorization, then rechecked completion', async () => {
  const m = mock(); const result = await processScreeningJob(m.options);
  assert.deepEqual(result, { state: 'clear', code: 'REVISION_CLEAR' });
  assert.deepEqual(m.calls.map(x => x.name), ['claim_content_screening', 'prepare_content_screening',
    'prepare_content_screening', 'prepare_content_screening', 'finish_content_screening']);
  assert.equal(m.calls.at(-2).args.p_authorize, true);
  assert.deepEqual(m.calls.at(-1).args, { p_job: id, p_lease: lease, p_outcome: 'clear' });
  assert.deepEqual(m.counts(), { downloads: 1, provider: 1 });
  assert(m.originals.every(x => x.every(v => v === 0))); assert(m.normalized.every(x => x.every(v => v === 0)));
});

test('four photos share one reservation and provider call; text-only needs no image processor', async () => {
  const m = mock(); m.input.images = Array.from({ length: 4 }, (_, i) => ({ ...m.input.images[0], path: `family/vault/photo-${i}.png` }));
  assert.equal((await processScreeningJob(m.options)).state, 'clear');
  assert.deepEqual(m.counts(), { downloads: 4, provider: 1 });
  assert.equal(m.calls.filter(c => c.args?.p_authorize === true).length, 1);
  const text = mock(); text.input.images = []; text.options.normalize = async () => assert.fail('No decode needed');
  assert.equal((await processScreeningJob(text.options)).state, 'clear');
  assert.deepEqual(text.counts(), { downloads: 0, provider: 1 });
});

test('invalid or duplicate source references and source-byte limits stop before any download', async () => {
  for (const change of [
    s => { s.images.push(s.images[0]); }, s => { s.images[0].path = '../../secret'; },
    s => { s.images = Array(5).fill(s.images[0]); }, s => { s.text = 'x'.repeat(20001); },
    s => { s.images = null; }, s => { s.revision = 'b'.repeat(64); },
    s => { delete s.processing_reserved; }, s => { s.processing_reserved = false; },
    s => { s.images = Array.from({ length: 3 }, (_, i) => ({ ...s.images[0], path: `family/vault/${i}.png`,
      metadata: { ...s.images[0].metadata, size: 12 * 1024 * 1024 } })); },
  ]) {
    const m = mock(); change(m.input);
    assert.equal((await processScreeningJob(m.options)).state, 'pending');
    assert.deepEqual(m.counts(), { downloads: 0, provider: 0 });
  }
});

test('claim errors, source withdrawal and denied authorization cannot reach the provider', async () => {
  for (const failureAt of ['claim', 'initial', 'before-photo', 'authorize']) {
    let prepares = 0;
    const m = mock({ rpc: async (name, args, input) => {
      if (name === 'claim_content_screening') return failureAt === 'claim' ? {} : { id, lease_token: lease, revision };
      assert.equal(name, 'prepare_content_screening'); prepares++;
      if ((failureAt === 'initial' && prepares === 1) || (failureAt === 'before-photo' && prepares === 2)) return { code: 'SOURCE_CHANGED' };
      if (args.p_authorize) return { code: 'BUDGET_LIMIT' };
      return input;
    } });
    assert.equal((await processScreeningJob(m.options)).state, 'pending'); assert.equal(m.counts().provider, 0);
  }
});

test('normalization errors and invalid outputs consume no provider request and erase downloaded bytes', async () => {
  for (const normalize of [async () => { throw new Error('private diagnostic'); }, async () => ({ mime: 'video/mp4', bytes: Buffer.from(photo) }),
    async () => ({ mime: 'image/jpeg', bytes: new Uint8Array(2 * 1024 * 1024 + 1) })]) {
    const m = mock(); const result = await processScreeningJob({ ...m.options, normalize });
    assert.equal(result.state, 'pending'); assert.equal(m.counts().provider, 0);
    assert.equal(m.calls.some(c => c.args?.p_authorize === true), false);
    assert(m.originals.every(x => x.every(v => v === 0)));
  }
});

test('provider clear is never returned when finish is stale, expired, missing or throws', async () => {
  for (const finish of [{ state: 'stale' }, { code: 'LEASE_UNAVAILABLE' }, null, 'throw']) {
    const m = mock({ rpc: async (name, args, input) => {
      if (name === 'claim_content_screening') return { id, lease_token: lease, revision };
      if (name === 'prepare_content_screening') return args.p_authorize ? { code: 'DISPATCH_RESERVED', revision } : input;
      if (finish === 'throw') throw new Error('private commit error');
      return finish;
    } });
    assert.notEqual((await processScreeningJob(m.options)).state, 'clear'); assert.equal(m.counts().provider, 1);
    assert.equal(m.calls.filter(c => c.name === 'finish_content_screening').length, 1);
  }
});

test('provider errors and flags reach finish as pending or review, never clear', async () => {
  for (const state of ['pending', 'review']) {
    const m = mock({ rpc: async (name, args, input) => {
      if (name === 'claim_content_screening') return { id, lease_token: lease, revision };
      if (name === 'prepare_content_screening') return args.p_authorize ? { code: 'DISPATCH_RESERVED', revision } : input;
      assert.equal(args.p_outcome, state); return { state: state === 'pending' ? 'queued' : 'review' };
    } });
    m.options.fetcher = async () => state === 'review' ? new Response(JSON.stringify(safeBody(true))) : new Response('secret', { status: 500 });
    assert.notEqual((await processScreeningJob(m.options)).state, 'clear');
  }
});

test('local DB to checked Storage bytes to mock provider to DB completion', { skip: !process.env.PGLITE_MODULE }, async t => {
  const { screeningFixture, consent, enqueue, clear, rpc } = await import('../../supabase/tests/helpers/screening_fixture.mjs');
  const { owner, memory, photoPath } = await import('../../supabase/tests/helpers/retirement_fixture.mjs');
  const wasm = await createWasmPhotoPreparer(await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm'))));
  for (const [decoder, normalize] of [['native', preparePhoto], ['wasm', wasm]]) {
  for (const change of ['none', 'edit-after-download', 'withdraw-before-dispatch', 'withdraw-during-request', 'delete-during-request']) {
    await t.test(`${decoder}-${change}`, async t => {
      const db = await screeningFixture(undefined, true, true); t.after(() => db.close());
      const etag = createHash('md5').update(photo).digest('hex');
      await db.query("update storage.objects set metadata=$1::jsonb where name=$2", [JSON.stringify({ eTag: etag,
        size: photo.length, mimetype: 'image/png' }), photoPath]);
      await enqueue(db); let providerCalls = 0;
      const client = createScreeningBackend({ serviceKey: 'test-only', fetcher: async (url, opts) => {
        if (url.includes('/storage/v1/')) {
          assert(url.endsWith(photoPath));
          if (change === 'edit-after-download') await db.query("update memories set body='Changed' where id=$1", [memory]);
          return new Response(photo, { headers: { etag: `"${etag}"`, 'content-type': 'image/png', 'content-length': String(photo.length) } });
        }
        const name = url.split('/').at(-1); const a = JSON.parse(opts.body); let value;
        if (name === 'claim_content_screening') value = await rpc(db, 'claim_content_screening()');
        else if (name === 'prepare_content_screening') {
          if (change === 'withdraw-before-dispatch' && a.p_authorize) await consent(db, owner, false);
          value = await rpc(db, 'prepare_content_screening($1,$2,$3)', [a.p_job, a.p_lease, a.p_authorize]);
        } else value = await rpc(db, 'finish_content_screening($1,$2,$3)', [a.p_job, a.p_lease, a.p_outcome]);
        return new Response(JSON.stringify(value));
      } });
      const result = await processScreeningJob({ enabled: true, apiKey: 'test-only', backend: client, normalize, fetcher: async (_, opts) => {
        providerCalls++; const payload = JSON.parse(opts.body);
        assert.equal(payload.input.length, 2);
        const decoded = Buffer.from(payload.input[1].image_url.url.split(',')[1], 'base64');
        assert.equal((await sharp(decoded).metadata()).exif, undefined);
        if (change === 'withdraw-during-request') await consent(db, owner, false);
        if (change === 'delete-during-request') await db.query('delete from memories where id=$1', [memory]);
        return new Response(JSON.stringify(safeBody()));
      } });
      assert.equal(await clear(db), change === 'none');
      assert.equal(result.state === 'clear', change === 'none');
      assert.equal(providerCalls, ['none', 'withdraw-during-request', 'delete-during-request'].includes(change) ? 1 : 0);
    });
  }
  }
});
