import { mkdtemp, mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash, randomFillSync } from 'node:crypto';
import sharp from 'sharp';

// Generates only offline disposable fixtures and copies checked sources. Does
// not authenticate, deploy, read app content or call any provider.
const args = process.argv.slice(2);
if (new Set(args).size !== args.length || args.some(a => !['--single-photo', '--bundled-wasm'].includes(a))) throw new Error('INVALID_ARGUMENTS');
const singlePhoto = args.includes('--single-photo');
const bundled = args.includes('--bundled-wasm');
const directory = await mkdtemp(join(tmpdir(), 'heiro-runtime-canary-'));
const target = join(directory, 'supabase', 'functions', 'screening_runtime_canary');
await mkdir(target, { recursive: true });
await mkdir(join(directory, 'fixtures'));
const source = new URL('../../supabase/verification/screening_runtime_canary/', import.meta.url);
await copyFile(new URL(bundled ? 'index_bundled.ts' : 'index.ts', source), join(target, 'index.ts'));
if (bundled) {
  // Avoid bundling the package's second decoder and duplicate binary assets.
  // Copy the pinned distribution unchanged and retain its license/notices.
  const moduleUrl = new URL(import.meta.resolve('@imagemagick/magick-wasm'));
  await copyFile(moduleUrl, join(target, 'magick.mjs'));
  await copyFile(new URL('../LICENSE', moduleUrl), join(target, 'MAGICK-LICENSE'));
  await copyFile(new URL('../NOTICE', moduleUrl), join(target, 'MAGICK-NOTICE'));
  await writeFile(join(target, 'deno.json'), JSON.stringify({ imports: { '@imagemagick/magick-wasm': './magick.mjs' } }, null, 2));
} else await copyFile(new URL('deno.json', source), join(target, 'deno.json'));
for (const name of ['runtime_canary.mjs', 'photo_wasm.mjs', 'photo_container.mjs', 'bundled_normalizer.mjs']) await copyFile(new URL(name, import.meta.url), join(target, name));
const fixtures = {};
for (const [name, width, height, batchCount, quality] of [
  ['small', 2048, 1536, 4, 84], ['large', 4032, 3024, 4, 60], ['high-resolution', 6000, 4000, 1, 50],
]) {
  const count = singlePhoto ? 1 : batchCount;
  const raw = randomFillSync(Buffer.alloc(width * height * 3));
  const bytes = await sharp(raw, { raw: { width, height, channels: 3 } }).jpeg({ quality }).toBuffer(); raw.fill(0);
  if (bytes.length > 12 * 1024 * 1024 || bytes.length * count > 24 * 1024 * 1024) throw new Error('GENERATED_FIXTURE_TOO_LARGE');
  fixtures[name] = { bytes: bytes.length, count, sha256: createHash('sha256').update(bytes).digest('hex') };
  await writeFile(join(directory, 'fixtures', `${name}.jpg`), bytes);
}
const wasm = await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')));
const configuration = { expiresAt: Date.now() + 30 * 60 * 1000, fixtures,
  binaryPackaging: bundled ? 'static-file' : 'pinned-cdn',
  binary: { bytes: wasm.length, sha256: createHash('sha256').update(wasm).digest('hex') } };
if (bundled) await writeFile(join(target, 'magick.wasm'), wasm);
wasm.fill(0);
await writeFile(join(target, 'fixtures.json'), JSON.stringify(configuration, null, 2));
// The regular project configuration is deliberately not copied or changed.
await writeFile(join(directory, 'supabase', 'config.toml'), 'project_id = "heiro-runtime-canary"\n[functions.screening_runtime_canary]\nverify_jwt = true\n' +
  (bundled ? 'static_files = ["./functions/screening_runtime_canary/magick.wasm", "./functions/screening_runtime_canary/MAGICK-LICENSE", "./functions/screening_runtime_canary/MAGICK-NOTICE"]\n' : ''));
console.log(JSON.stringify({ directory, mode: singlePhoto ? 'single-photo' : 'batch',
  binaryPackaging: configuration.binaryPackaging,
  expiresAt: new Date(configuration.expiresAt).toISOString(), fixtureNames: Object.keys(fixtures) }));
