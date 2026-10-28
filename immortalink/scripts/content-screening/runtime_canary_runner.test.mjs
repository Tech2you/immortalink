import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const runner = fileURLToPath(new URL('../../supabase/verification/screening_runtime_canary/run.mjs', import.meta.url));
const key = 'eyJhbGciOiJIUzI1NiJ9.' + Buffer.from(JSON.stringify({
  role: 'service_role', ref: 'vbzyvaylfdhwowdbodmk', exp: 4102444800,
})).toString('base64url') + '.fake-test-signature';
const stub = `#!${process.execPath}
const fs = require('node:fs'), path = require('node:path');
const statePath = process.env.HEIRO_TEST_STATE;
const state = JSON.parse(fs.readFileSync(statePath));
const args = process.argv.slice(2), tool = path.basename(process.argv[1]);
state.calls.push({ tool, args });
const save = () => fs.writeFileSync(statePath, JSON.stringify(state));
const base = Array.from({length: 10}, (_, i) => ({id: 'existing-' + i, name: 'existing-' + i,
  version: state.scenario === 'changed-existing' && state.deleted ? 2 : 1,
  status: 'ACTIVE', verify_jwt: true, ezbr_sha256: 'unchanged'}));
if (tool === 'supabase') {
  if (args[0] === 'functions' && args[1] === 'list') {
    if (state.deployed) base.push({id: 'diagnostic', name: 'screening_runtime_canary',
      version: 1, status: 'ACTIVE', verify_jwt: state.scenario !== 'missing-jwt', ezbr_sha256: 'test'});
    console.log(JSON.stringify(base));
  } else if (args[0] === 'projects' && args[1] === 'api-keys') {
    console.log(JSON.stringify([{name:'service_role', api_key: process.env.HEIRO_TEST_KEY},
      {name:'anon', api_key:'fake-anon-key'}]));
  } else if (args[1] === 'deploy') {
    state.deployed = true;
  } else if (args[1] === 'delete') {
    if (state.scenario === 'cleanup-failure') process.exitCode = 1;
    else { state.deployed = false; state.deleted = true; }
  } else process.exitCode = 1;
} else if (tool === 'docker') {
  if (state.scenario === 'docker-missing') process.exitCode = 1;
  else console.log('local-test-docker');
} else if (tool === 'curl') {
  const headers = fs.readFileSync(0, 'utf8');
  const fixture = new URL(args.at(-1)).searchParams.get('fixture');
  const authorized = headers.includes('x-heiro-canary-key: ' + process.env.HEIRO_TEST_KEY);
  let status = 200, body;
  if (!authorized) status = state.scenario === 'auth-open' ? 200 : 401;
  else if (args[args.indexOf('--request') + 1] === 'GET') status = 405;
  else if (args[args.indexOf('--data-binary') + 1] === '') status = 413;
  else if (state.scenario === 'fixture-failure' && fixture === 'large') status = 546;
  if (status === 200) body = {fixture, completed: 1, wallMs: 10, outputBytes: 3, serializedBytes: 10};
  else body = {code: 'TEST_REJECTION'};
  console.log(JSON.stringify(body) + '\\n' + status + '\\n0');
} else process.exitCode = 1;
save();
`;

for (const scenario of ['success', 'fixture-failure', 'auth-open', 'missing-jwt',
  'cleanup-failure', 'changed-existing', 'expired', 'missing-approval',
  'bundled-success', 'bundled-mismatch', 'docker-missing', 'packaging-missing']) {
  test(`operator canary runner: ${scenario} (fake CLI and transport only)`, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'heiro-runtime-canary-runner-test-'));
    try {
      const bin = join(directory, 'bin'), target = join(directory, 'supabase/functions/screening_runtime_canary');
      await mkdir(bin); await mkdir(target, { recursive: true }); await mkdir(join(directory, 'fixtures'));
      for (const tool of ['supabase', 'curl', 'docker']) await writeFile(join(bin, tool), stub, { mode: 0o700 });
      const fixtures = {};
      for (const name of ['small', 'large', 'high-resolution']) {
        fixtures[name] = { count: 1 };
        await writeFile(join(directory, 'fixtures', name + '.jpg'), 'generated-test-placeholder');
      }
      const bundled = scenario.startsWith('bundled-') || scenario === 'docker-missing';
      const asset = Buffer.from('local-generated-placeholder');
      await writeFile(join(target, 'magick.wasm'), asset);
      await writeFile(join(target, 'fixtures.json'), JSON.stringify({ fixtures,
        binaryPackaging: scenario === 'packaging-missing' ? undefined : bundled ? 'static-file' : 'pinned-cdn',
        binary: { bytes: asset.length, sha256: scenario === 'bundled-mismatch' ? '0'.repeat(64) : createHash('sha256').update(asset).digest('hex') },
        expiresAt: Date.now() + (scenario === 'expired' ? -1000 : 20 * 60 * 1000) }));
      const statePath = join(directory, 'stub-state.json');
      await writeFile(statePath, JSON.stringify({ scenario, deployed: false, calls: [] }));
      const args = scenario === 'missing-approval' ? [runner] : [runner, '--approved-generated-only', directory];
      // PATH contains only our stubs, so this test cannot invoke a real CLI/curl.
      const child = spawnSync(process.execPath, args, { encoding: 'utf8', timeout: 15000,
        env: { PATH: bin, HEIRO_TEST_STATE: statePath, HEIRO_TEST_KEY: key } });
      assert.ifError(child.error);
      assert.equal(child.status, ['success', 'bundled-success'].includes(scenario) ? 0 : 1);
      assert.equal((child.stdout + child.stderr).includes(key), false);
      const state = JSON.parse(await readFile(statePath, 'utf8'));
      assert.equal(JSON.stringify(state.calls).includes(key), false, 'Credentials never enter argv');
      if (scenario === 'missing-approval') { assert.deepEqual(state.calls, []); return; }
      const result = JSON.parse(await readFile(join(directory, 'diagnostic-result.json'), 'utf8'));
      assert.equal(JSON.stringify(result).includes(key), false);
      if (['expired', 'bundled-mismatch', 'docker-missing', 'packaging-missing'].includes(scenario)) {
        assert(state.calls.every(c => c.args[1] === 'list' || c.tool === 'docker'));
        assert.equal(result.deployed, undefined);
      } else {
        assert(state.calls.some(c => c.tool === 'supabase' && c.args[1] === 'delete'));
        assert.equal(result.diagnosticAbsent, scenario !== 'cleanup-failure');
        assert.equal(result.existingFunctionsUnchanged, scenario !== 'changed-existing');
        const config = await readFile(join(target, 'fixtures.json'), 'utf8');
        assert.equal(config.includes(key), false, 'Only a fingerprint is persisted');
        if (['success', 'bundled-success'].includes(scenario)) assert.equal(result.probes.length, 7);
        const deploy = state.calls.find(c => c.tool === 'supabase' && c.args[1] === 'deploy');
        assert.equal(deploy.args.includes('--use-api'), !bundled);
        if (scenario === 'fixture-failure') assert.equal(result.probes.at(-1).label, 'large');
        if (scenario === 'auth-open') assert.equal(result.probes.length, 2);
        if (scenario === 'missing-jwt') assert.equal(result.probes.length, 0);
      }
    } finally { await rm(directory, { recursive: true, force: true }); }
  });
}
