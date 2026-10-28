import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { base, newState, validateState, paths, checkedSignedURL, probeResult,
  makeClient, cleanup, recoverCreatedUsers, retireFixture } from './media_link_live_qa.mjs';

function fixture() {
  const state = newState();
  state.users = [0, 1].map(index => ({ id: randomUUID(), email: `heiro-media-qa-${state.run}-${index}@example.invalid` }));
  return state;
}

test('fixture identity and media paths are generated, bounded and tied to this run', () => {
  const state = fixture();
  assert.equal(validateState(state), state);
  for (const path of Object.values(paths(state))) assert.ok(path.startsWith(`${state.users[0].id}/${state.vault}/memories/`));
  for (const change of [
    state => { state.project = 'other'; },
    state => { state.users[0].email = 'real@example.com'; },
    state => { state.users[1].id = state.users[0].id; },
    state => { state.memories.push(randomUUID()); },
    state => { state.family = '../other'; },
    state => { state.cleanedUsers.push(randomUUID()); },
    state => { state.mode = 'arbitrary'; },
  ]) {
    const changed = fixture(); change(changed);
    assert.throws(() => validateState(changed));
  }
});

test('signed link accepts only this project and the exact generated file', () => {
  const path = paths(fixture()).original;
  const suffix = `/object/sign/vault_photos/${path}?token=safe-test-token`;
  assert.equal(checkedSignedURL(suffix, path), `${base}/storage/v1${suffix}`);
  assert.equal(checkedSignedURL(`${base}/storage/v1${suffix}`, path), `${base}/storage/v1${suffix}`);
  for (const url of [
    `https://evil.example/storage/v1${suffix}`, `https://other@${new URL(base).host}/storage/v1${suffix}`,
    `${base}/storage/v1${suffix}#fragment`, suffix.replace(path, 'other/photo.png'),
    suffix.replace('?token=safe-test-token', ''), '//evil.example/file',
  ]) assert.throws(() => checkedSignedURL(url, path));
});

test('probe never mistakes a 200 error page or a server failure for the fixture', () => {
  const headers = new Headers({ 'cache-control': 'max-age=3600', 'cf-cache-status': 'HIT', age: '20' });
  const result = probeResult(200, headers, Buffer.from('not the test image'));
  assert.deepEqual(result, { status: 200, cache: 'HIT', cacheControl: 'max-age=3600', age: '20', matchesFixture: false });
  assert.equal(probeResult(503, headers, Buffer.from('error')).matchesFixture, false);
  assert.ok(!JSON.stringify(result).includes('token'));
});

test('requests fix the host, prohibit redirects and redact upstream error details', async () => {
  const calls = [];
  const client = makeClient({ admin: 'server-secret', anon: 'public-key', fetchImpl: async (url, options) => {
    calls.push({ url, options });
    return new Response(JSON.stringify({ message: 'server-secret private family content' }), { status: 403 });
  } });
  await assert.rejects(client.request('/rest/v1/example'), error => error.message === 'QA request failed (HTTP 403).');
  assert.equal(calls[0].url, `${base}/rest/v1/example`);
  assert.equal(calls[0].options.redirect, 'error');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer server-secret');
  await assert.rejects(client.request('//evil.example'), /QA check failed/);
  assert.equal(calls.length, 1);
});

test('password reset refuses an account lacking the server-side fixture tag', async () => {
  const state = fixture(); const calls = [];
  const client = makeClient({ admin: 'secret', anon: 'anon', fetchImpl: async (url, options) => {
    calls.push(options.method);
    return new Response(JSON.stringify({ id: state.users[0].id, email: state.users[0].email, app_metadata: {} }));
  } });
  await assert.rejects(client.token(state, 0), /refuse non-fixture account/);
  assert.deepEqual(calls, ['GET']);
});

test('cleanup accepts a successful void RPC response without trying to read a null body', async () => {
  const client = makeClient({ admin: 'secret', anon: 'anon', fetchImpl: async () => new Response(null, { status: 204 }) });
  assert.equal(await client.rpc('review_content_report', {}), null);
});

test('lost create responses recover only exact tagged fixture identities', async () => {
  const state = newState(), id = randomUUID(); let saved = 0;
  const userEmail = `heiro-media-qa-${state.run}-0@example.invalid`;
  await recoverCreatedUsers(state, { request: async () => ({ data: { users: [
    { id: randomUUID(), email: userEmail, app_metadata: {} },
    { id, email: userEmail, app_metadata: { heiro_media_qa: state.run } },
    { id: randomUUID(), email: 'real@example.com', app_metadata: { heiro_media_qa: state.run } },
  ] } }) }, async () => { saved++; });
  assert.deepEqual(state.users, [{ id, email: userEmail }]); assert.equal(saved, 1);
});

test('cleanup refuses a family with a non-fixture member before deleting anything', async () => {
  const state = fixture(); let writes = 0;
  const client = { request: async path => {
    if (path.startsWith('/auth/v1/admin/users?')) return { data: { users: [] } };
    if (path.startsWith('/rest/v1/family_groups')) return { data: [{ id: state.family,
      name: `Heiro media-link QA ${state.run}`, created_by: state.users[0].id }] };
    if (path.startsWith('/rest/v1/family_members')) return { data: [{ user_id: randomUUID() }] };
    writes++; throw new Error('unexpected write');
  } };
  await assert.rejects(cleanup(state, client, async () => {}), /unexpected family member/);
  assert.equal(writes, 0);
});

test('cleanup refuses a non-fixture report before restoring it', async () => {
  const state = fixture(); state.reports.push(randomUUID()); let actions = 0;
  const client = { request: async path => {
    if (path.startsWith('/auth/v1/admin/users?')) return { data: { users: [] } };
    if (path.startsWith('/rest/v1/family_groups')) return { data: [] };
    return { data: [{ target_kind: 'memory', target_id: state.memories[0], details: 'real report' }] };
  }, rpc: async () => { actions++; } };
  await assert.rejects(cleanup(state, client, async () => {}), /refuse non-fixture moderation/);
  assert.equal(actions, 0);
});

test('partial fixture cleanup verifies deletion, is retryable and never deletes an untagged account', async () => {
  const state = fixture(); state.mode = 'integrated'; state.reports.push(randomUUID());
  let accountDeletes = 0; const deleted = new Set(); const actions = [];
  const client = {
    request: async (path, options = {}) => {
      if (path.startsWith('/auth/v1/admin/users?')) return { data: { users: [] } };
      if (path.startsWith('/rest/v1/family_groups') || path.startsWith('/storage/')) return { data: [] };
      if (path.startsWith('/rest/v1/content_reports')) return { data: [{ target_kind: 'memory',
        target_id: state.memories[0], details: `Heiro media-link QA ${state.run}` }] };
      if (path.startsWith('/auth/v1/admin/users/')) return { ok: true, status: deleted.has(path.split('/').at(-1)) ? 404 : 200 };
      if (path === '/functions/v1/delete_account') {
        accountDeletes++; deleted.add(options.token); return { ok: true, data: { ok: true } };
      }
      throw new Error('unexpected request');
    },
    token: async (fixtureState, index) => fixtureState.users[index].id,
    rpc: async name => {
      assert.equal(accountDeletes, 2, 'account deletion must not depend on restoring pending media');
      actions.push(name);
    },
  };
  await cleanup(state, client, async () => {});
  assert.equal(state.cleanupComplete, true); assert.equal(accountDeletes, 2);
  assert.deepEqual(actions, ['next_content_media_retirement', 'review_content_report']);
  await cleanup(state, client, async () => {});
  assert.equal(accountDeletes, 2);
});

test('integrated worker moves only the exact generated source, even if the backend returns another job', async () => {
  for (const wrongSource of [false, true]) {
    const state = fixture(); state.mode = 'integrated'; state.reports.push(randomUUID());
    const original = paths(state).original;
    const source = wrongSource ? original.replace(state.memories[0], state.memories[1]) : original;
    const destination = `${source.slice(0, source.lastIndexOf('/'))}/${randomUUID()}.png`;
    let reads = 0; const moves = [];
    const client = { request: async (path, { body }) => {
      if (path.endsWith('next_content_media_retirement')) return { data: ++reads === 1
        ? { id: randomUUID(), bucket: 'vault_photos', source, destination } : null };
      if (path === '/storage/v1/object/move') { moves.push(body); return { data: {} }; }
      return { data: { state: moves.length ? 'retired' : 'pending' } };
    } };
    const result = await retireFixture(state, client, state.reports[0]);
    assert.equal(moves.length, wrongSource ? 0 : 1);
    assert.equal(result.state, wrongSource ? 'pending' : 'retired');
    await assert.rejects(retireFixture(state, client, randomUUID()), /fixture report/);
  }
});
