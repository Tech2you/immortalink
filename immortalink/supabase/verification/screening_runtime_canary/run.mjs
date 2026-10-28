import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

// Operator-only diagnostic. Obtain explicit deployment approval before running.
const [approval, directory, ...extra] = process.argv.slice(2);
if (approval !== '--approved-generated-only' || extra.length ||
    !directory || !directory.includes('/heiro-runtime-canary-')) {
  throw new Error('Usage: run.mjs --approved-generated-only <generated-temporary-directory>');
}
const project = 'vbzyvaylfdhwowdbodmk';
const name = 'screening_runtime_canary';
const cli = args => execFileSync('supabase', args, {
  encoding: 'utf8', timeout: 120000, maxBuffer: 2 * 1024 * 1024,
  stdio: ['ignore', 'pipe', 'pipe'],
});
const list = () => JSON.parse(cli(['functions', 'list', '--project-ref', project, '--output', 'json']));
const identity = rows => JSON.stringify(rows.map(row => Object.fromEntries(
  ['id', 'name', 'version', 'status', 'verify_jwt', 'ezbr_sha256'].map(key => [key, row[key]])
)).sort((a, b) => a.name.localeCompare(b.name)));
const result = { startedAt: new Date().toISOString(), probes: [] };
let before, attempted = false, phase = 'baseline';
try {
  before = list();
  if (!Array.isArray(before) || before.length !== 10 || before.some(row => row.name === name)) throw new Error('BASELINE_MISMATCH');
  result.existingFunctions = before.length;
  await writeFile(join(directory, 'function-baseline.json'), JSON.stringify(before, null, 2));
  const configuration = JSON.parse(await readFile(join(directory, 'supabase/functions', name, 'fixtures.json'), 'utf8'));
  const remaining = configuration.expiresAt - Date.now();
  if (!Number.isFinite(remaining) || remaining < 10 * 60 * 1000 || remaining > 30 * 60 * 1000) throw new Error('FIXTURE_EXPIRY_INVALID');
  if (!['pinned-cdn', 'static-file'].includes(configuration.binaryPackaging)) throw new Error('BINARY_PACKAGING_REQUIRED');
  result.binaryPackaging = configuration.binaryPackaging;
  if (configuration.binaryPackaging === 'static-file') {
    phase = 'bundled-asset-check';
    const binary = await readFile(join(directory, 'supabase/functions', name, 'magick.wasm'));
    try {
      if (binary.length !== configuration.binary?.bytes || createHash('sha256').update(binary).digest('hex') !== configuration.binary?.sha256) throw new Error('BUNDLED_ASSET_MISMATCH');
    } finally { binary.fill(0); }
    // No fallback to a network loader or server-side bundling if Docker is absent.
    execFileSync('docker', ['info', '--format', '{{.ServerVersion}}'], { encoding: 'utf8', timeout: 15000, stdio: ['ignore', 'pipe', 'pipe'] });
  }
  result.fixtureCounts = Object.fromEntries(Object.entries(configuration.fixtures).map(([key, f]) => [key, f.count]));
  phase = 'credentials';
  const keys = JSON.parse(cli(['projects', 'api-keys', '--project-ref', project, '--output', 'json']));
  const service = keys.find(key => key.name === 'service_role')?.api_key;
  const anon = keys.find(key => key.name === 'anon')?.api_key;
  if (typeof service !== 'string' || !service.startsWith('eyJ') || typeof anon !== 'string') throw new Error('KEYS_UNAVAILABLE');
  // Sanity check only; the enabled Supabase gateway verifies the JWT signature.
  const claims = JSON.parse(Buffer.from(service.split('.')[1], 'base64url').toString('utf8'));
  if (claims.role !== 'service_role' || claims.ref !== project || claims.exp * 1000 < Date.now()) throw new Error('WRONG_TEST_KEY');
  configuration.serviceKeySha256 = createHash('sha256').update(service).digest('hex');
  await writeFile(join(directory, 'supabase/functions', name, 'fixtures.json'), JSON.stringify(configuration, null, 2));
  phase = 'deploy'; attempted = true;
  cli(['functions', 'deploy', name, '--project-ref', project,
    ...(configuration.binaryPackaging === 'pinned-cdn' ? ['--use-api'] : []), '--workdir', directory, '--yes']);
  result.deployed = true;
  const deployed = list().find(row => row.name === name);
  result.diagnosticId = deployed?.id;
  if (!deployed?.verify_jwt) throw new Error('GATEWAY_VERIFICATION_REQUIRED');
  console.log(JSON.stringify({ phase: 'deployed', name, diagnosticId: result.diagnosticId }));
  const endpoint = `https://${project}.supabase.co/functions/v1/${name}`;
  const probe = async (label, fixture, credential, bytes, method = 'POST') => {
    const start = Date.now();
    // Pass the secret only over stdin, never in argv or a file.
    const config = credential ? `header = "Authorization: Bearer ${credential}"\nheader = "x-heiro-canary-key: ${credential}"\n` : '';
    let output = '', transportExit = 0;
    try {
      output = execFileSync('curl', ['--silent', '--show-error', '--http1.1',
        '--connect-timeout', '15', '--max-time', '40', '--config', '-', '--request', method,
        '--header', 'content-type: application/octet-stream', '--header', 'Expect:',
        '--data-binary', bytes.length ? `@${join(directory, 'fixtures', `${fixture}.jpg`)}` : '',
        '--write-out', '\n%{http_code}\n%{size_upload}', `${endpoint}?fixture=${fixture}`],
      { encoding: 'utf8', input: config, timeout: 45000, maxBuffer: 512 * 1024,
        stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (error) { output = String(error.stdout || ''); transportExit = error.status || -1; }
    const lines = output.trimEnd().split('\n');
    const uploadedBytes = Number(lines.pop()), status = Number(lines.pop());
    let data = {};
    try { data = JSON.parse(lines.join('\n')); } catch {}
    const safe = {};
    for (const key of ['completed', 'outputBytes', 'serializedBytes', 'wallMs']) {
      if (Number.isFinite(data[key])) safe[key] = data[key];
    }
    if (data.fixture === fixture) safe.fixture = fixture;
    if (typeof data.code === 'string' && /^[A-Z_]{1,80}$/.test(data.code)) safe.code = data.code;
    const outcome = { label, status, uploadedBytes, transportExit, clientMs: Date.now() - start, ...safe };
    result.probes.push(outcome); console.log(JSON.stringify(outcome));
    if (transportExit) throw new Error('TRANSPORT_FAILED');
    return outcome;
  };
  phase = 'authorization-probes';
  // Rejection must happen before reading a body; avoid a large rejected upload.
  await probe('no-credential', 'small', null, new Uint8Array());
  await probe('public-app-key', 'small', anon, new Uint8Array());
  if (result.probes.some(p => p.status !== 401)) throw new Error('AUTHORIZATION_PROBE_FAILED');
  phase = 'service-key-controls';
  if ((await probe('service-get', 'small', service, new Uint8Array(), 'GET')).status !== 405) throw new Error('SERVICE_GET_FAILED');
  if ((await probe('service-empty-body', 'small', service, new Uint8Array())).status !== 413) throw new Error('SERVICE_BODY_CONTROL_FAILED');
  phase = 'generated-fixtures';
  for (const fixture of ['small', 'large', 'high-resolution']) {
    const bytes = await readFile(join(directory, 'fixtures', `${fixture}.jpg`));
    try {
      const outcome = await probe(fixture, fixture, service, bytes);
      if (outcome.status !== 200 || outcome.completed !== configuration.fixtures[fixture].count) throw new Error('FIXTURE_FAILED');
    } finally { bytes.fill(0); }
  }
} catch (error) {
  result.failure = { phase, code: typeof error?.status === 'number' ? `COMMAND_EXIT_${error.status}` : error?.name || 'Error' };
  console.log(JSON.stringify({ failure: result.failure }));
} finally {
  if (attempted) {
    try { cli(['functions', 'delete', name, '--project-ref', project, '--yes']); result.deleteCommandCompleted = true; }
    catch { result.deleteCommandCompleted = false; }
  }
  if (before) {
    try {
      const after = list();
      result.diagnosticAbsent = !after.some(row => row.name === name);
      result.existingFunctionsUnchanged = identity(after.filter(row => row.name !== name)) === identity(before);
    } catch { result.cleanupVerificationUnavailable = true; }
  }
  result.finishedAt = new Date().toISOString();
  await writeFile(join(directory, 'diagnostic-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
  if (result.failure || !result.diagnosticAbsent || !result.existingFunctionsUnchanged) process.exitCode = 1;
}
