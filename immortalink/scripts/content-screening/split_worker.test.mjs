import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import sharp from 'sharp';
import { processScreeningJob } from './worker.mjs';
import { createScreeningBackend } from './backend.mjs';
import { createPhotoPreparationHandler, createRemotePhotoPreparer } from './photo_transport.mjs';
import { photoDigest } from './photo_job.mjs';
import { preparePhoto } from './photo.mjs';
import { createWasmPhotoPreparer } from './photo_wasm.mjs';
import { SCREENING_CATEGORIES } from '../../supabase/functions/_shared/content_screening.mjs';
import { consent, request, clear, rpc } from '../../supabase/tests/helpers/screening_fixture.mjs';
import { asUser } from '../../supabase/tests/helpers/publication_fixture.mjs';
import { reviewFixture, queue, inspected, decide } from '../../supabase/tests/helpers/screening_review_fixture.mjs';
import { owner, viewer, vault, memory, photoPath, ids } from '../../supabase/tests/helpers/retirement_fixture.mjs';

const photo = await sharp({ create: { width: 32, height: 24, channels: 3, background: '#36924a' } })
  .withExif({ IFD0: { Artist: 'PRIVATE EXIF TEST' } }).jpeg().toBuffer();
const etag = createHash('md5').update(photo).digest('hex');
const token = 'disposable-local-worker-test-'.repeat(2);
const safeBody = flagged => ({ results: [{ flagged,
  categories: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, false])),
  category_scores: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, 0.01])),
}] });
const sql = {
  claim_content_screening: () => ['claim_content_screening()', []],
  prepare_content_screening: a => ['prepare_content_screening($1,$2,$3)', [a.p_job, a.p_lease, a.p_authorize]],
  finish_content_screening: a => ['finish_content_screening($1,$2,$3)', [a.p_job, a.p_lease, a.p_outcome]],
  claim_content_screening_photo: a => ['claim_content_screening_photo($1,$2,$3)', [a.p_job, a.p_lease, a.p_index]],
  finish_content_screening_photo: a => ['finish_content_screening_photo($1,$2,$3)', [a.p_ticket, a.p_bytes, a.p_sha256]],
};

test('local DB, checked Storage, separate photo HTTP requests and one aggregate mock classifier', {
  skip: !process.env.PGLITE_MODULE, timeout: 120000,
}, async t => {
  const wasm = await createWasmPhotoPreparer(await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm'))));
  for (const scenario of ['four-native', 'four-wasm', 'text-only', 'flagged', 'edit-after-download', 'withdraw-after-decode',
    'delete-account-after-decode', 'withdraw-after-response', 'withdraw-before-authorize', 'withdraw-during-provider',
    'delete-during-provider', 'manifest-tampered', 'child-failed', 'budget-exhausted']) {
    await t.test(scenario, async t => {
      const db = await reviewFixture(); t.after(() => db.close());
      await db.exec('create or replace function everroot_limit_bigint(uuid,text) returns bigint language sql as $$select 1073741824::bigint$$');
      const count = scenario.startsWith('four-') ? 4 : scenario === 'text-only' ? 0 : 1;
      for (let i = 1; i < count; i++) {
        const path = photoPath.replace('photo.png', `photo-${i}.jpg`);
        await db.query('insert into memory_photos(vault_id,memory_id,path) values($1,$2,$3)', [vault, memory, path]);
        await db.query('insert into storage.objects(bucket_id,name,owner,owner_id,metadata) select bucket_id,$1,owner,owner_id,metadata from storage.objects where name=$2', [path, photoPath]);
      }
      if (!count) await db.exec('delete from memory_photos');
      await db.query('update storage.objects set metadata=$1::jsonb', [JSON.stringify({ eTag: etag, size: photo.length, mimetype: 'image/jpeg' })]);
      assert.equal((await request(db)).state, 'queued');
      assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, 0);
      if (scenario === 'budget-exhausted') await db.exec("update content_safety.screening_processing_limits set max_output_bytes=1 where scope='global_day'");
      const storageBefore = (await db.query('select * from storage.objects order by id')).rows;
      let downloads = 0, childCalls = 0, providerCalls = 0, authorizations = 0;
      const owned = [], remote = [];
      const backend = createScreeningBackend({ serviceKey: 'local-only', fetcher: async (url, init) => {
        if (url.includes('/storage/v1/')) {
          assert.equal(init.method, 'GET'); downloads++;
          assert(url.includes(`/vault_photos/${owner}/${vault}/memories/${memory}/`));
          assert.equal(init.headers['If-Match'], `"${etag}"`);
          if (scenario === 'edit-after-download') await db.query("update memories set body='Changed' where id=$1", [memory]);
          return new Response(photo, { headers: { etag: `"${etag}"`, 'content-type': 'image/jpeg', 'content-length': String(photo.length) } });
        }
        const name = url.split('/').at(-1), args = JSON.parse(init.body);
        assert(Object.hasOwn(sql, name)); assert.equal(init.method, 'POST');
        if (args.p_authorize) {
          authorizations++;
          if (scenario === 'withdraw-before-authorize') await consent(db, owner, false);
        }
        const value = await rpc(db, ...sql[name](args));
        if (scenario === 'manifest-tampered' && value?.prepared_images?.length) value.prepared_images[0].sha256 = 'b'.repeat(64);
        return Response.json(value);
      } });
      const handler = createPhotoPreparationHandler({ enabled: true, workerTokenSha256: photoDigest(token), backend,
        normalize: async (bytes, mime) => {
          owned.push(bytes);
          const result = await (scenario === 'four-wasm' ? wasm : preparePhoto)(bytes, mime); owned.push(result.bytes);
          if (scenario === 'withdraw-after-decode') await consent(db, owner, false);
          if (scenario === 'delete-account-after-decode') await db.query('select claim_account_deletion($1,$2)', [owner, ids[15]]);
          return result;
        } });
      const prepareImage = createRemotePhotoPreparer({ gatewayKey: 'local-only', workerToken: token, fetcher: async (url, init) => {
        childCalls++;
        if (scenario === 'child-failed') return new Response('', { status: 503 });
        const response = await handler(new Request(url, init));
        if (scenario === 'withdraw-after-response') await consent(db, owner, false);
        return response;
      } });
      const result = await processScreeningJob({ enabled: true, apiKey: 'mock-only', backend,
        prepareImage: async (...args) => { const image = await prepareImage(...args); remote.push(image.bytes); return image; },
        fetcher: async (url, init) => {
          providerCalls++; assert.equal(url, 'https://api.openai.com/v1/moderations');
          const payload = JSON.parse(init.body); assert.equal(payload.input.length, count + 1);
          for (const item of payload.input.filter(i => i.type === 'image_url')) {
            const bytes = Buffer.from(item.image_url.url.split(',')[1], 'base64');
            const metadata = await sharp(bytes).metadata(); assert.equal(metadata.exif, undefined); assert.equal(metadata.xmp, undefined);
          }
          if (scenario === 'withdraw-during-provider') await consent(db, owner, false);
          if (scenario === 'delete-during-provider') await db.query('delete from memories where id=$1', [memory]);
          return Response.json(safeBody(scenario === 'flagged'));
        } });
      const succeeds = ['four-native', 'four-wasm', 'text-only'].includes(scenario);
      const dispatches = succeeds || ['flagged', 'withdraw-during-provider', 'delete-during-provider'].includes(scenario);
      const diagnostic = JSON.stringify({ result, downloads, childCalls, providerCalls, authorizations });
      assert.equal(result.state === 'clear', succeeds, diagnostic); assert.equal(await clear(db), succeeds);
      assert.equal((await asUser(db, viewer, 'select id from memories where id=$1', [memory])).rows.length, succeeds ? 1 : 0);
      assert.equal((await asUser(db, viewer, 'select * from memory_photos where memory_id=$1', [memory])).rows.length, succeeds ? count : 0);
      assert.equal(providerCalls, dispatches ? 1 : 0, diagnostic);
      if (scenario === 'flagged') assert.equal(result.state, 'review');
      assert.equal(childCalls, scenario === 'budget-exhausted' ? 0 : count);
      assert.equal(downloads, ['child-failed', 'budget-exhausted'].includes(scenario) ? 0 : count);
      assert.equal(owned.length, ['child-failed', 'budget-exhausted'].includes(scenario) ? 0 : count * 2);
      assert(authorizations <= 1); assert(owned.every(b => b.every(x => x === 0))); assert(remote.every(b => b.every(x => x === 0)));
      assert.deepEqual((await db.query('select * from storage.objects order by id')).rows, storageBefore);
      const tickets = (await db.query('select * from content_safety.screening_photo_tickets')).rows;
      assert(tickets.length <= count); assert(tickets.every(row => !Object.values(row).some(v => v instanceof Uint8Array)));
      if(scenario==='flagged'){
        const cases=await queue(db);assert.equal(cases.length,1);
        const held=await inspected(db,cases[0].id);await decide(db,cases[0].id,held.revision);
        assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length,1);
        assert.equal(providerCalls,1);
      } else assert.deepEqual(await queue(db),[]);
    });
  }
});
