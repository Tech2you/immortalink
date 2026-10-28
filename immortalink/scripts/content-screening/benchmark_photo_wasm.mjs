import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash, randomFillSync } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// Explicit offline benchmark: generated noise fixtures only, no app data/keys.
// Child processes isolate decoder memory evidence from native fixture generation.
if (process.argv[2] === '--decode-generated-fixture') {
  const { createWasmPhotoPreparer } = await import('./photo_wasm.mjs');
  const { createRuntimeCanary } = await import('./runtime_canary.mjs');
  const cpuStart = process.cpuUsage(), start = performance.now();
  const input = await readFile(process.argv[3]);
  const count = Number(process.argv[4]);
  const fixture = { bytes: input.length, count, sha256: createHash('sha256').update(input).digest('hex') };
  const key = 'generated-test-only-key';
  const handler = createRuntimeCanary({ serviceKeySha256: createHash('sha256').update(key).digest('hex'), expiresAt: Date.now() + 60000,
    fixtures: { test: fixture, unused1: fixture, unused2: fixture },
    loadNormalizer: async () => createWasmPhotoPreparer(await readFile(new URL(import.meta.resolve('@imagemagick/magick-wasm/magick.wasm')))) });
  const response = await handler(new Request('https://example.invalid/canary?fixture=test', { method: 'POST',
    headers: { authorization: `Bearer ${key}`, 'x-heiro-canary-key': key, 'content-type': 'application/octet-stream' }, body: input }));
  const result = await response.json();
  const cpu = process.cpuUsage(cpuStart);
  console.log(JSON.stringify({ attempted: count, completed: result.completed ?? 0, failure: response.status !== 200,
    inputBytes: input.length * count, outputBytes: result.outputBytes, serializedBytes: result.serializedBytes,
    coldCpuMs: Math.round((cpu.user + cpu.system) / 1000), coldWallMs: Math.round(performance.now() - start),
    peakRssMiB: Math.round(process.resourceUsage().maxRSS / 1024) }));
} else {
  const { default: sharp } = await import('sharp');
  const directory = await mkdtemp(join(tmpdir(), 'heiro-generated-screening-'));
  try {
    for (const [width, height, count, quality] of [[2048, 1536, 4, 84], [4032, 3024, 4, 60], [6000, 4000, 1, 50]]) {
      const file = join(directory, `${width}.jpg`);
      const raw = randomFillSync(Buffer.alloc(width * height * 3));
      await writeFile(file, await sharp(raw, { raw: { width, height, channels: 3 } }).jpeg({ quality }).toBuffer());
      raw.fill(0);
      const run = spawnSync(process.execPath, [new URL(import.meta.url).pathname, '--decode-generated-fixture', file, String(count)],
        { encoding: 'utf8', timeout: 15000, maxBuffer: 4096, env: { PATH: process.env.PATH } });
      if (run.status !== 0) throw new Error('GENERATED_IMAGE_BENCHMARK_FAILED');
      console.log(JSON.stringify({ width, height, ...JSON.parse(run.stdout) }));
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
}
