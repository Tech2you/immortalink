import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, stat, copyFile } from 'node:fs/promises';
import { join, isAbsolute } from 'node:path';
import { brotliCompressSync, constants } from 'node:zlib';

// Local diagnostic only: no Supabase CLI, credentials, database or AI calls.
const [approval, directory, ...extra] = process.argv.slice(2);
if (approval !== '--approved-local-only' || extra.length || !directory ||
    !isAbsolute(directory) || !directory.startsWith('/private/tmp/heiro-local-bundle.') ||
    !/\/heiro-runtime-canary-[A-Za-z0-9]+$/.test(directory)) {
  throw new Error('Usage: run_local.mjs --approved-local-only <generated-local-build-directory>');
}
const image = 'supabase/edge-runtime@sha256:d5b0545da7826404668c3a53809f217a9c7093526c7036c18e79ddc61e4cbe01';
const context = 'colima-heiro-build';
const docker = args => execFileSync('docker', ['--context', context, ...args], {
  encoding: 'utf8', timeout: 180000, maxBuffer: 2 * 1024 * 1024,
  stdio: ['ignore', 'pipe', 'pipe'],
});
const source = join(directory, 'supabase/functions/screening_runtime_canary');
const output = join(directory, 'local-output');
const configPath = join(source, 'fixtures.json');
const config = JSON.parse(await readFile(configPath, 'utf8'));
assert.equal(config.binaryPackaging, 'static-file');
assert(config.expiresAt > Date.now() + 5 * 60 * 1000);
const binary = await readFile(join(source, 'magick.wasm'));
try {
  assert.equal(binary.length, config.binary.bytes);
  assert.equal(createHash('sha256').update(binary).digest('hex'), config.binary.sha256);
} finally { binary.fill(0); }
const secret = randomBytes(32).toString('hex');
const name = `heiro-bundle-local-${randomBytes(6).toString('hex')}`;
config.serviceKeySha256 = createHash('sha256').update(secret).digest('hex');
await writeFile(configPath, JSON.stringify(config, null, 2));
await mkdir(output, { recursive: true });
const router = join(directory, 'local-router');
await mkdir(router, { recursive: true });
await copyFile(new URL('./local_router.ts', import.meta.url), join(router, 'index.ts'));
const events = join(directory, 'local-events');
await mkdir(events, { recursive: true });
await copyFile(new URL('./local_events.ts', import.meta.url), join(events, 'index.ts'));
const result = { startedAt: new Date().toISOString(), image, context,
  kind: 'local-bundled-runtime-only', probes: [] };
let started = false, phase = 'bundle';
try {
  docker(['run', '--rm', '--pull', 'never', '--network', 'none', '--cpus', '2', '--memory', '1g',
    '-e', 'DENO_NO_PACKAGE_JSON=1', '-v', `${source}:/source:ro`, '-v', `${output}:/output:rw`,
    '-w', '/source', image, 'bundle', '--entrypoint', '/source/index.ts',
    '--static', '/source/magick.wasm', '--static', '/source/MAGICK-LICENSE', '--static', '/source/MAGICK-NOTICE',
    '--output', '/output/diagnostic.eszip', '--timeout', '120']);
  result.bundleBytes = (await stat(join(output, 'diagnostic.eszip'))).size;
  const bundled = await readFile(join(output, 'diagnostic.eszip'));
  result.bundleSha256 = createHash('sha256').update(bundled).digest('hex');
  result.brotliQuality6Bytes = brotliCompressSync(bundled, { params: { [constants.BROTLI_PARAM_QUALITY]: 6 } }).length;
  bundled.fill(0);
  assert(result.bundleBytes < 20 * 1024 * 1024, 'BUNDLE_TOO_LARGE');
  // Only the bundle is mounted at runtime, not the original static asset/source.
  phase = 'start';
  started = true;
  docker(['run', '-d', '--pull', 'never', '--name', name, '--cpus', '2', '--memory', '512m',
    '-p', '127.0.0.1::9000', '-v', `${output}:/bundle:ro`, '-v', `${router}:/router:ro`,
    '-v', `${events}:/events:ro`, image, 'start',
    '--main-service', '/router', '--event-worker', '/events', '--max-parallelism', '1', '--policy', 'oneshot']);
  const port = docker(['port', name, '9000/tcp']).trim();
  assert.match(port, /^127\.0\.0\.1:\d+$/);
  const endpoint = `http://${port}/?fixture=`;
  phase = 'readiness';
  let ready = false;
  for (let i = 0; i < 30; i++) {
    try {
      const response = await fetch(endpoint + 'small', { signal: AbortSignal.timeout(1000) });
      assert.equal(response.status, 401); await response.arrayBuffer(); ready = true; break;
    } catch { await new Promise(resolve => setTimeout(resolve, 250)); }
  }
  assert(ready, 'LOCAL_RUNTIME_NOT_READY');
  result.probes.push({ label: 'no-credential', status: 401 });
  for (const fixture of ['small', 'large', 'high-resolution']) {
    phase = fixture;
    const bytes = await readFile(join(directory, 'fixtures', `${fixture}.jpg`));
    try {
      assert.equal(createHash('sha256').update(bytes).digest('hex'), config.fixtures[fixture].sha256);
      const response = await fetch(endpoint + fixture, { method: 'POST',
        headers: { 'content-type': 'application/octet-stream', 'x-heiro-canary-key': secret },
        body: bytes, signal: AbortSignal.timeout(30000), redirect: 'error' });
      const data = await response.json();
      const safe = { label: fixture, status: response.status };
      for (const field of ['completed', 'outputBytes', 'serializedBytes', 'wallMs']) {
        if (Number.isFinite(data[field])) safe[field] = data[field];
      }
      result.probes.push(safe);
      assert.equal(response.status, 200, 'LOCAL_FIXTURE_FAILED');
      assert.equal(data.completed, 1);
    } finally { bytes.fill(0); }
  }
} catch (error) {
  result.failure = { phase, code: typeof error?.status === 'number' ? `COMMAND_EXIT_${error.status}` : error?.code || error?.name || 'Error' };
  process.exitCode = 1;
} finally {
  if (started) {
    try {
      result.containerState = JSON.parse(docker(['inspect', '--format', '{{json .State}}', name]));
      result.containerState = { oomKilled: result.containerState.OOMKilled, exitCode: result.containerState.ExitCode,
        running: result.containerState.Running };
      const logged = spawnSync('docker', ['--context', context, 'logs', name], { encoding: 'utf8', timeout: 10000, maxBuffer: 2 * 1024 * 1024 });
      assert.equal(logged.status, 0);
      const logs = logged.stdout + logged.stderr;
      result.stages = Array.from(logs.matchAll(/CANARY_STAGE ([a-z_]+)/g), match => match[1]);
      result.binaryVerified = result.stages.includes('bundled_binary_verified');
      result.decoderInitialized = result.stages.includes('wasm_init_ready');
      if (!result.failure && (!result.binaryVerified || !result.decoderInitialized)) {
        result.failure = { phase: 'logs', code: 'LOADER_PROOF_MISSING' }; process.exitCode = 1;
      }
    } catch { result.logsUnavailable = true; process.exitCode = 1; }
    try { docker(['rm', '-f', name]); result.containerRemoved = true; }
    catch { result.containerRemoved = false; process.exitCode = 1; }
  }
  delete config.serviceKeySha256;
  await writeFile(configPath, JSON.stringify(config, null, 2));
  result.finishedAt = new Date().toISOString();
  await writeFile(join(directory, 'local-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
}
