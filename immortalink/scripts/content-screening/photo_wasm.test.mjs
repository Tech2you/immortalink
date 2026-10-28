import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import sharp from 'sharp';
import { createWasmPhotoPreparer, WASM_PHOTO_LIMITS } from './photo_wasm.mjs';

const wasm = await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')));
const prepare = await createWasmPhotoPreparer(wasm);
const create = (width = 32, height = 16) => sharp({ create: { width, height, channels: 3, background: '#218458' } });

test('WASM JPEG/PNG/WebP output is opaque, oriented and stripped without changing originals', async () => {
  for (const [format, mime] of [['jpeg', 'image/jpeg'], ['png', 'image/png'], ['webp', 'image/webp']]) {
    const bytes = await create().toFormat(format).withMetadata({ orientation: 6 })
      .withExifMerge({ IFD0: { Artist: 'PRIVATE TEST NAME', Copyright: 'PRIVATE TEST LOCATION' } })
      .withXmp('<x:xmpmeta xmlns:x="adobe:ns:meta/">PRIVATE TEST METADATA</x:xmpmeta>').toBuffer();
    const original = Buffer.from(bytes);
    const output = await prepare(bytes, mime);
    const meta = await sharp(output.bytes).metadata();
    assert.equal(output.mime, 'image/jpeg'); assert.equal(meta.width, 16); assert.equal(meta.height, 32);
    for (const key of ['exif', 'xmp', 'iptc', 'icc', 'orientation']) assert.equal(meta[key], undefined);
    assert.equal(meta.hasAlpha, false); assert(output.bytes.length <= WASM_PHOTO_LIMITS.outputBytes);
    assert.equal(Buffer.from(output.bytes).includes(Buffer.from('PRIVATE')), false);
    assert.deepEqual(bytes, original);
  }
});

test('WASM JPEG shrink-on-load bounds a 24 MP photo without cropping or enlarging small images', async () => {
  for (const [w, h, outW, outH] of [[6000, 4000, 1024, 683], [4032, 3024, 1024, 768],
    [2048, 1536, 1024, 768], [1500, 1000, 1024, 683], [128, 64, 128, 64]]) {
    const input = await create(w, h).jpeg().toBuffer(), original = Buffer.from(input);
    const result = await prepare(input, 'image/jpeg');
    const meta = await sharp(result.bytes).metadata();
    assert.equal(meta.width, outW); assert(Math.abs(meta.height - outH) <= 1);
    assert.deepEqual(input, original);
  }
});

test('WASM rejects truncated, mismatched, active, unsupported and oversized inputs', async () => {
  const png = await create().png().toBuffer(), jpg = await create().jpeg().toBuffer();
  for (const [bytes, mime] of [[Buffer.alloc(0), 'image/png'], [Buffer.alloc(WASM_PHOTO_LIMITS.inputBytes + 1), 'image/png'],
    [png, 'image/jpeg'], [png, 'image/heic'], [png.subarray(0, 30), 'image/png'],
    [jpg.subarray(0, jpg.length - 20), 'image/jpeg'], [Buffer.from('<svg/>'), 'image/png']]) {
    await assert.rejects(prepare(bytes, mime), { message: 'PHOTO_PREPARATION_FAILED' });
  }
  const corrupt = Buffer.from(png); corrupt.fill(0, 41, corrupt.length - 12);
  await assert.rejects(prepare(corrupt, 'image/png'), { message: 'PHOTO_PREPARATION_FAILED' });
});

test('WASM rejects animation and multi-picture headers instead of checking only one frame', async () => {
  const animation = await sharp({ create: { width: 16, height: 32, pageHeight: 16, channels: 3,
    noise: { type: 'gaussian' } } }).webp({ loop: 0, delay: [100, 100] }).toBuffer();
  await assert.rejects(prepare(animation, 'image/webp'), { message: 'PHOTO_PREPARATION_FAILED' });
  const png = await create().png().toBuffer();
  const marker = Buffer.alloc(20); marker.writeUInt32BE(8); marker.write('acTL', 4);
  await assert.rejects(prepare(Buffer.concat([png.subarray(0, 33), marker, png.subarray(33)]), 'image/png'), { message: 'PHOTO_PREPARATION_FAILED' });
  const jpg = await create().jpeg().toBuffer();
  const mpf = Buffer.from([255, 226, 0, 6, 77, 80, 70, 0]);
  await assert.rejects(prepare(Buffer.concat([jpg.subarray(0, 2), mpf, jpg.subarray(2)]), 'image/jpeg'), { message: 'PHOTO_PREPARATION_FAILED' });
});

test('WASM resource exhaustion and over-pixel limits fail closed and do not poison later jobs', async () => {
  for (const [w, h] of [[6000, 5000], [6000, 4000]]) {
    const bytes = await create(w, h).png().toBuffer();
    await assert.rejects(prepare(bytes, 'image/png'), { message: 'PHOTO_PREPARATION_FAILED' });
  }
  assert.equal((await prepare(await create().png().toBuffer(), 'image/png')).mime, 'image/jpeg');
});

test('WASM cooperative deadline prevents returning a completed image after its time allowance', async t => {
  const bytes = await create().jpeg().toBuffer();
  let elapsed = 0;
  t.mock.method(performance, 'now', () => (elapsed += 1000));
  await assert.rejects(prepare(bytes, 'image/jpeg'), { message: 'PHOTO_PREPARATION_FAILED' });
});
