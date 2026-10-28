import { test } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { preparePhoto, PHOTO_LIMITS } from './photo.mjs';

const create = (width = 32, height = 16) => sharp({ create: { width, height, channels: 3, background: '#218458' } });

test('JPEG, PNG and WebP decode to bounded opaque JPEG without metadata', async () => {
  for (const [format, mime] of [['jpeg', 'image/jpeg'], ['png', 'image/png'], ['webp', 'image/webp']]) {
    const bytes = await create().toFormat(format).withMetadata({ orientation: 6 })
      .withExifMerge({ IFD0: { Artist: 'PRIVATE TEST NAME', Copyright: 'PRIVATE GPS TEST' } })
      .withXmp('<x:xmpmeta xmlns:x="adobe:ns:meta/">PRIVATE TEST METADATA</x:xmpmeta>').toBuffer();
    const original = Buffer.from(bytes);
    const meta = await sharp(bytes).metadata(); assert(meta.exif); assert(meta.xmp);
    const output = await preparePhoto(bytes, mime);
    const after = await sharp(output.bytes).metadata();
    assert.equal(output.mime, 'image/jpeg'); assert.equal(after.format, 'jpeg');
    assert.equal(after.width, 16); assert.equal(after.height, 32);
    for (const key of ['exif', 'xmp', 'iptc', 'icc', 'orientation']) assert.equal(after[key], undefined);
    assert.equal(after.hasAlpha, false); assert(output.bytes.length <= PHOTO_LIMITS.outputBytes);
    assert.equal(Buffer.from(output.bytes).includes(Buffer.from('PRIVATE')), false);
    assert.deepEqual(bytes, original, 'Preparing never changes stored/original bytes');
  }
});

test('large still images resize without cropping or enlarging small pictures', async () => {
  const output = await preparePhoto(await create(4096, 2048).png().toBuffer(), 'image/png');
  const meta = await sharp(output.bytes).metadata();
  assert.equal(meta.width, 2048); assert.equal(meta.height, 1024);
});

test('truncated, mismatched, oversized, active and unsupported inputs fail closed', async () => {
  const png = await create().png().toBuffer();
  const jpeg = await create().jpeg().toBuffer();
  for (const [bytes, mime] of [
    [Buffer.alloc(0), 'image/png'], [Buffer.alloc(PHOTO_LIMITS.inputBytes + 1), 'image/png'],
    [png, 'image/jpeg'], [png, 'image/heic'], [jpeg.subarray(0, jpeg.length - 20), 'image/jpeg'],
    [png.subarray(0, 30), 'image/png'], [Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'), 'image/png'],
    [new Uint8Array([255, 216, 255]), 'image/jpeg'],
  ]) await assert.rejects(preparePhoto(bytes, mime), { message: 'PHOTO_PREPARATION_FAILED' });
});

test('over-pixel-limit images and animated WebP/APNG are never reduced to a single checked frame', async () => {
  const huge = await create(6000, 5000).png().toBuffer();
  await assert.rejects(preparePhoto(huge, 'image/png'), { message: 'PHOTO_PREPARATION_FAILED' });
  const animation = await sharp({ create: { width: 16, height: 32, pageHeight: 16, channels: 3,
    noise: { type: 'gaussian' } } }).webp({ loop: 0, delay: [100, 100] }).toBuffer();
  assert.equal((await sharp(animation).metadata()).pages, 2);
  await assert.rejects(preparePhoto(animation, 'image/webp'), { message: 'PHOTO_PREPARATION_FAILED' });
  const png = await create().png().toBuffer();
  const animationMarker = Buffer.alloc(20); animationMarker.writeUInt32BE(8); animationMarker.write('acTL', 4);
  await assert.rejects(preparePhoto(Buffer.concat([png.subarray(0, 33), animationMarker, png.subarray(33)]), 'image/png'),
    { message: 'PHOTO_PREPARATION_FAILED' });
});
