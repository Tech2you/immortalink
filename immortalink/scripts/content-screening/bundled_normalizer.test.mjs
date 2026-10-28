import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import sharp from 'sharp';
import { createBundledNormalizerLoader } from './bundled_normalizer.mjs';
import { createWasmPhotoPreparer } from './photo_wasm.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const fake = () => Uint8Array.from([0, 97, 115, 109, 1, 0, 0, 0]);

test('bundled loader rejects invalid configuration before reading or initializing', () => {
  const config = { bytes: 8, sha256: digest(fake()), readBinary: async () => assert.fail('must not read'), createPreparer: async () => assert.fail('must not initialize') };
  for (const patch of [{ bytes: 0 }, { bytes: 20971521 }, { sha256: '' }, { sha256: null },
    { readBinary: null }, { createPreparer: null }, { onStage: null }]) {
    assert.throws(() => createBundledNormalizerLoader({ ...config, ...patch }), /BUNDLED_DECODER_UNAVAILABLE/);
  }
});

test('concurrent callers share one pinned asset read and one initialization; buffers are cleared', async () => {
  const binary = fake(), stages = []; let reads = 0, inits = 0;
  const prepare = async () => {};
  const load = createBundledNormalizerLoader({ bytes: 8, sha256: digest(binary), onStage: s => stages.push(s),
    readBinary: async expected => { reads++; assert.equal(expected, 8); return binary; },
    createPreparer: async input => { inits++; assert.deepEqual(input, fake()); return prepare; },
  });
  const first = load(), second = load(); assert.equal(first, second);
  assert.equal(await first, prepare); assert.equal(await second, prepare); assert.equal(await load(), prepare);
  assert.equal(reads, 1); assert.equal(inits, 1); assert(binary.every(x => x === 0));
  assert.deepEqual(stages, ['bundled_binary_read_started', 'bundled_binary_verified', 'wasm_init_ready']);
});

test('missing, changed or incorrectly sized asset cannot initialize or retry', async () => {
  for (const mode of ['missing', 'hash', 'size', 'type']) {
    const binary = fake(); let reads = 0;
    const load = createBundledNormalizerLoader({ bytes: mode === 'size' ? 9 : 8,
      sha256: mode === 'hash' ? '0'.repeat(64) : digest(binary),
      readBinary: async () => { reads++; if (mode === 'missing') throw new Error('PRIVATE FILE PATH'); return mode === 'type' ? 'invalid' : binary; },
      createPreparer: async () => assert.fail('Unverified code must not initialize'),
    });
    for (let i = 0; i < 2; i++) await assert.rejects(load(), { message: 'BUNDLED_DECODER_UNAVAILABLE' });
    assert.equal(reads, 1);
    if (mode === 'size' || mode === 'hash') assert(binary.every(x => x === 0));
  }
});

test('initialization failure stays failed, observer failure cannot bypass integrity checks', async () => {
  const binary = fake(); let inits = 0;
  const load = createBundledNormalizerLoader({ bytes: 8, sha256: digest(binary), readBinary: async () => binary,
    onStage: () => { throw new Error('observer failure'); },
    createPreparer: async () => { inits++; throw new Error('PRIVATE DECODER ERROR'); },
  });
  await assert.rejects(load(), { message: 'BUNDLED_DECODER_UNAVAILABLE' });
  await assert.rejects(load(), { message: 'BUNDLED_DECODER_UNAVAILABLE' });
  assert.equal(inits, 1); assert(binary.every(x => x === 0));
});

test('installed pinned binary initializes and processes generated JPEG with no network loader', async () => {
  const binary = await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')));
  const fetchBefore = globalThis.fetch;
  globalThis.fetch = async () => assert.fail('Bundled initialization must not fetch');
  try {
    const load = createBundledNormalizerLoader({ bytes: binary.length, sha256: digest(binary),
      readBinary: async () => binary, createPreparer: createWasmPhotoPreparer });
    const normalize = await load(); assert(binary.every(x => x === 0));
    const input = await sharp({ create: { width: 64, height: 32, channels: 3, background: '#228855' } })
      .withExif({ IFD0: { Artist: 'PRIVATE TEST METADATA' } }).jpeg().toBuffer();
    const output = await normalize(input, 'image/jpeg');
    const metadata = await sharp(output.bytes).metadata();
    assert.equal(metadata.width, 64); assert.equal(metadata.height, 32); assert.equal(metadata.exif, undefined);
    input.fill(0); output.bytes.fill(0);
  } finally { globalThis.fetch = fetchBefore; }
});

test('offline bundling copies pinned binary/module and notices without importing the full npm package', { timeout: 30000 }, async () => {
  const script = fileURLToPath(new URL('./prepare_runtime_canary.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [script, '--single-photo', '--bundled-wasm'], { encoding: 'utf8', timeout: 25000 });
  assert.ifError(result.error); assert.equal(result.status, 0, result.stderr);
  const info = JSON.parse(result.stdout);
  try {
    assert.equal(info.binaryPackaging, 'static-file'); assert.equal(info.mode, 'single-photo');
    const root = join(info.directory, 'supabase/functions/screening_runtime_canary');
    const config = JSON.parse(await readFile(join(root, 'fixtures.json'), 'utf8'));
    const copied = await readFile(join(root, 'magick.wasm'));
    const installed = await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')));
    assert.deepEqual(copied, installed); assert.equal(config.binary.bytes, copied.length);
    assert.equal(config.binary.sha256, digest(copied)); assert.equal(config.serviceKeySha256, undefined);
    const toml = await readFile(join(info.directory, 'supabase/config.toml'), 'utf8');
    assert.match(toml, /verify_jwt = true/);
    assert.match(toml, /static_files = \["\.\/functions\/screening_runtime_canary\/magick\.wasm", "\.\/functions\/screening_runtime_canary\/MAGICK-LICENSE", "\.\/functions\/screening_runtime_canary\/MAGICK-NOTICE"\]/);
    const moduleUrl = new URL(import.meta.resolve('@imagemagick/magick-wasm'));
    assert.deepEqual(await readFile(join(root, 'magick.mjs')), await readFile(moduleUrl));
    for (const name of ['LICENSE', 'NOTICE']) assert.deepEqual(await readFile(join(root, 'MAGICK-' + name)), await readFile(new URL('../' + name, moduleUrl)));
    assert.deepEqual(JSON.parse(await readFile(join(root, 'deno.json'), 'utf8')), { imports: { '@imagemagick/magick-wasm': './magick.mjs' } });
    const entrypoint = await readFile(join(root, 'index.ts'), 'utf8');
    assert.doesNotMatch(entrypoint, /Deno\.stat\(/); assert.match(entrypoint, /Deno\.readFile\(binaryPath\)/);
    assert.doesNotMatch(entrypoint, /fetch\(|createCanaryNormalizerLoader/);
    for (const [name, fixture] of Object.entries(config.fixtures)) {
      const bytes = await readFile(join(info.directory, 'fixtures', name + '.jpg'));
      assert.equal(fixture.count, 1); assert.equal(fixture.sha256, digest(bytes)); assert.equal(fixture.bytes, bytes.length);
    }
  } finally { await rm(info.directory, { recursive: true, force: true }); }
});
