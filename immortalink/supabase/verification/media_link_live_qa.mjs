// Opt-in live experiment, not a production takedown worker. Fixture IDs are
// generated here; no existing account, memory, object path or URL is accepted.
import { execFileSync } from 'node:child_process';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { readFile, writeFile, rename } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { readBounded } from '../../scripts/content_review_server.mjs';
import { retireReportMedia, moveRequest } from '../../scripts/retire_report_media.mjs';

export const project = 'vbzyvaylfdhwowdbodmk';
export const base = `https://${project}.supabase.co`;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jFuoAAAAASUVORK5CYII=', 'base64');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const check = (condition, label) => { if (!condition) throw new Error(`QA check failed: ${label}`); };
const label = state => `Heiro media-link QA ${state.run}`;
const email = (state, index) => `heiro-media-qa-${state.run}-${index}@example.invalid`;

export function newState(mode = 'experiment') {
  return { version: 1, mode, project, run: randomUUID(), family: randomUUID(), vault: randomUUID(),
    memories: [randomUUID(), randomUUID()], photos: [randomUUID(), randomUUID()],
    users: [], reports: [], evidence: {}, cleanedUsers: [], complete: false };
}

export function validateState(state) {
  check(state?.version === 1 && state.project === project, 'fixture project');
  check(state.mode === undefined || ['experiment', 'integrated'].includes(state.mode), 'fixture mode');
  const ids = [state.run, state.family, state.vault, ...state.memories ?? [], ...state.photos ?? []];
  check(state.memories?.length === 2 && state.photos?.length === 2
    && ids.every(id => typeof id === 'string' && uuid.test(id)) && new Set(ids).size === 7, 'fixture IDs');
  check(Array.isArray(state.users) && state.users.length <= 2 && Array.isArray(state.reports)
    && state.reports.length <= 1 && state.reports.every(id => uuid.test(id)), 'fixture accounts and reports');
  check(state.users.every((user, index) => uuid.test(user.id) && user.email === email(state, index)), 'fixture identity');
  check(new Set(state.users.map(user => user.id)).size === state.users.length, 'distinct fixture accounts');
  check(Array.isArray(state.cleanedUsers) && state.cleanedUsers.every(id => state.users.some(user => user.id === id)), 'cleanup identity');
  return state;
}

export function paths(state) {
  validateState(state);
  check(state.users.length === 2, 'both fixture accounts exist');
  const prefix = `${state.users[0].id}/${state.vault}/memories/`;
  return {
    original: `${prefix}${state.memories[0]}/original.png`,
    retired: `${prefix}${state.memories[0]}/retired-${state.run}.png`,
    sibling: `${prefix}${state.memories[1]}/sibling.png`,
    adminSource: `${prefix}${state.memories[0]}/admin-move-source.png`,
    adminTarget: `${prefix}${state.memories[0]}/admin-move-target.png`,
  };
}

export function checkedSignedURL(value, expectedPath) {
  check(typeof value === 'string', 'signed link returned');
  const result = new URL(value.startsWith('/object/sign/') ? `/storage/v1${value}` : value, base);
  const expected = `/storage/v1/object/sign/vault_photos/${expectedPath}`;
  check(result.origin === base && !result.username && !result.password && !result.hash
    && decodeURIComponent(result.pathname) === expected && !!result.searchParams.get('token'), 'signed link scope');
  return result.href;
}

export function probeResult(status, headers, bytes) {
  return { status, cache: headers.get('cf-cache-status'), cacheControl: headers.get('cache-control'),
    age: headers.get('age'), matchesFixture: status === 200 && hash(bytes) === hash(png) };
}

export function makeClient({ admin, anon, fetchImpl = fetch }) {
  async function request(path, { token = admin, method = 'GET', body, bytes, allowError = false } = {}) {
    check(path.startsWith('/') && !path.startsWith('//') && !/[\r\n]/.test(path), 'request path');
    const response = await fetchImpl(`${base}${path}`, {
      method, redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { apikey: token === admin ? admin : anon, Authorization: `Bearer ${token}`,
        ...(body === undefined ? {} : { 'Content-Type': 'application/json', Prefer: 'return=representation' }),
        ...(bytes ? { 'Content-Type': 'image/png', 'Cache-Control': 'max-age=3600' } : {}) },
      body: bytes ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
    const raw = response.body ? await readBounded(response.body, 1024 * 1024) : Buffer.alloc(0);
    let data; try { data = JSON.parse(raw.toString()); } catch { data = null; }
    // Upstream errors and response bodies may contain credentials. Never print them.
    if (!response.ok && !allowError) throw new Error(`QA request failed (HTTP ${response.status}).`);
    return { status: response.status, ok: response.ok, data };
  }
  return {
    request,
    rpc: async (name, body, token = admin) => (await request(`/rest/v1/rpc/${name}`, { method: 'POST', body, token })).data,
    probe: async (url, expectedPath) => {
      checkedSignedURL(url, expectedPath);
      const response = await fetchImpl(url, { redirect: 'error', signal: AbortSignal.timeout(15000) });
      return probeResult(response.status, response.headers, await readBounded(response.body, 16384));
    },
    token: async (state, index) => {
      const user = state.users[index];
      const found = (await request(`/auth/v1/admin/users/${user.id}`)).data;
      check(found?.id === user.id && found.email === email(state, index)
        && found.app_metadata?.heiro_media_qa === state.run, 'refuse non-fixture account');
      const password = `${randomBytes(32).toString('base64url')}aA1!`;
      await request(`/auth/v1/admin/users/${user.id}`, { method: 'PUT', body: { password } });
      const auth = (await request('/auth/v1/token?grant_type=password', {
        token: anon, method: 'POST', body: { email: user.email, password },
      })).data;
      check(auth?.user?.id === user.id && typeof auth.access_token === 'string', 'fixture session');
      return auth.access_token;
    },
  };
}

export async function recoverCreatedUsers(state, client, save) {
  // A create-user response may be lost. Recover ONLY exact, server-tagged QA
  // identities; never reset a password based on an email alone.
  for (let page = 1; page <= 10; page++) {
    const result = (await client.request(`/auth/v1/admin/users?page=${page}&per_page=100`)).data;
    check(Array.isArray(result?.users), 'fixture account recovery');
    for (let index = state.users.length; index < 2; index++) {
      const user = result.users.find(item => item.email === email(state, index)
        && item.app_metadata?.heiro_media_qa === state.run);
      if (user) {
        check(index === state.users.length && uuid.test(user.id), 'fixture recovery order');
        state.users.push({ id: user.id, email: user.email }); await save();
      }
    }
    if (result.users.length < 100) return;
  }
  throw new Error('QA account recovery exceeded its bound; inspect fixture cleanup.');
}

export async function cleanup(state, client, save) {
  validateState(state);
  await recoverCreatedUsers(state, client, save);
  const families = (await client.request(`/rest/v1/family_groups?id=eq.${state.family}&select=id,name,created_by`)).data;
  check(Array.isArray(families) && families.length <= 1, 'cleanup family lookup');
  if (families.length) {
    check(families[0].name === label(state) && state.users.some(user => user.id === families[0].created_by), 'refuse non-fixture family');
    const members = (await client.request(`/rest/v1/family_members?family_id=eq.${state.family}&select=user_id`)).data;
    check(Array.isArray(members) && members.every(member => state.users.some(user => user.id === member.user_id)), 'unexpected family member; stop cleanup');
  }
  for (const id of state.reports) {
    const rows = (await client.request(`/rest/v1/content_reports?id=eq.${id}&select=id,target_kind,target_id,details`)).data;
    check(rows?.length === 1 && rows[0].target_kind === 'memory' && rows[0].target_id === state.memories[0]
      && rows[0].details === label(state), 'refuse non-fixture moderation');
  }
  // Use the existing, tested deletion workflow, not hand-written cascade deletes.
  for (const [index, user] of state.users.entries()) {
    if (state.cleanedUsers.includes(user.id)) continue;
    const found = await client.request(`/auth/v1/admin/users/${user.id}`, { allowError: true });
    if (found.status === 404) { state.cleanedUsers.push(user.id); await save(); continue; }
    check(found.ok, 'cleanup account lookup');
    const token = await client.token(state, index);
    const result = await client.request('/functions/v1/delete_account', { token, method: 'POST', body: {}, allowError: true });
    check(result.ok && result.data?.ok === true, 'fixture deletion incomplete; run --cleanup');
    check((await client.request(`/auth/v1/admin/users/${user.id}`, { allowError: true })).status === 404, 'fixture account removed');
    state.cleanedUsers.push(user.id); await save();
  }
  const remaining = (await client.request(`/rest/v1/family_groups?id=eq.${state.family}&select=id`)).data;
  check(Array.isArray(remaining) && remaining.length === 0, 'fixture family removed');
  if (state.users.length === 2) {
    const objects = (await client.request('/storage/v1/object/list/vault_photos', {
      method: 'POST', body: { prefix: `${state.users[0].id}/${state.vault}/`, limit: 100 },
    })).data;
    check(Array.isArray(objects) && objects.length === 0, 'fixture storage removed');
  }
  // Do not make deletion depend on finishing a failed Storage move. Once the
  // fixture bytes are gone, reconcile pending jobs before clearing its hide.
  for (const id of state.reports) {
    if (state.mode === 'integrated') await client.rpc('next_content_media_retirement', { p_report_id: id });
    await client.rpc('review_content_report', { p_report_id: id, p_action: 'restore',
      p_reviewer: 'Disposable media QA', p_notes: `${label(state)} cleanup` });
  }
  state.cleanupComplete = true; await save();
}

export async function retireFixture(state, client, report) {
  const original = paths(state).original;
  check(state.mode === 'integrated' && state.reports.length === 1 && state.reports[0] === report, 'integrated fixture report');
  return retireReportMedia(async (path, body) => {
    if (path === '/storage/v1/object/move') {
      // The shared worker validates the job. This additional fixture boundary
      // prevents a mistaken backend job from moving an existing family object.
      moveRequest({ id: state.run, bucket: body.bucketId, source: body.sourceKey, destination: body.destinationKey });
      check(body.bucketId === 'vault_photos' && body.sourceKey === original, 'refuse non-fixture move');
    } else {
      check(['/rest/v1/rpc/next_content_media_retirement', '/rest/v1/rpc/content_report_media_status'].includes(path)
        && body.p_report_id === report, 'fixture retirement request');
    }
    return (await client.request(path, { method: 'POST', body })).data;
  }, report);
}

export async function runExperiment(state, client, save, { sleep = pause } = {}) {
  const { request, rpc } = client;
  const record = async (name, data) => { state.evidence[name] = data; await save(); console.log(`RECORDED ${name}`); };
  const insert = async (table, body, token) => (await request(`/rest/v1/${table}`, { method: 'POST', body, token })).data;
  for (let index = 0; index < 2; index++) {
    const body = { email: email(state, index), password: `${randomBytes(32).toString('base64url')}aA1!`,
      email_confirm: true, app_metadata: { heiro_media_qa: state.run } };
    const user = (await request('/auth/v1/admin/users', { method: 'POST', body })).data;
    check(uuid.test(user?.id) && user.email === body.email, 'created fixture identity');
    state.users.push({ id: user.id, email: user.email }); await save();
  }
  const owner = await client.token(state, 0), viewer = await client.token(state, 1);
  await insert('family_groups', { id: state.family, name: label(state), created_by: state.users[0].id });
  for (const [index, user] of state.users.entries()) {
    await insert('family_members', { family_id: state.family, user_id: user.id, role: index ? 'member' : 'owner', is_primary: true });
  }
  await insert('vaults', { id: state.vault, owner_id: state.users[0].id, family_id: state.family, name: label(state) });
  const files = paths(state);
  for (const [index, memory] of state.memories.entries()) {
    await insert('memories', { id: memory, vault_id: state.vault, life_stage: 'mid', prompt_key: 'media_link_qa',
      prompt_text: label(state), body: 'Harmless generated media-link QA fixture', share_to_family_feed: true }, owner);
    const path = index ? files.sibling : files.original;
    await request(`/storage/v1/object/vault_photos/${path}`, { method: 'POST', token: owner, bytes: png });
    await insert('memory_photos', { id: state.photos[index], vault_id: state.vault, memory_id: memory, path }, owner);
  }
  const sign = async path => {
    const result = await request(`/storage/v1/object/sign/vault_photos/${path}`, {
      method: 'POST', token: viewer, body: { expiresIn: 3600 },
    });
    return checkedSignedURL(result.data?.signedURL, path);
  };
  const copiedLink = await sign(files.original), siblingLink = await sign(files.sibling);
  const warm = [];
  for (let n = 0; n < 3; n++) warm.push(await client.probe(copiedLink, files.original));
  check(warm.every(item => item.matchesFixture), 'baseline photo bytes'); await record('beforeHide', warm);
  const report = await rpc('report_family_content', { p_kind: 'memory', p_target_id: state.memories[0],
    p_reason: 'other', p_details: label(state), p_family_id: state.family }, viewer);
  check(uuid.test(report), 'fixture report'); state.reports.push(report); await save();
  const act = async action => {
    const preview = await rpc('preview_content_report', { p_report_id: report, p_reviewer: 'Disposable media QA' });
    return rpc('review_content_report_checked', { p_report_id: report, p_action: action,
      p_reviewer: 'Disposable media QA', p_notes: label(state), p_revision: preview.revision });
  };
  await act('hide');
  const hiddenRows = (await request(`/rest/v1/memories?id=eq.${state.memories[0]}&select=id`, { token: viewer })).data;
  check(Array.isArray(hiddenRows) && hiddenRows.length === 0, 'hidden memory denied');
  const deniedSign = await request(`/storage/v1/object/sign/vault_photos/${files.original}`, {
    method: 'POST', token: viewer, body: { expiresIn: 3600 }, allowError: true,
  });
  check([400, 401, 403, 404].includes(deniedSign.status) && !deniedSign.data?.signedURL, 'hidden new signing denied');
  await record('hiddenOldLink', await client.probe(copiedLink, files.original));
  await record('hiddenOldLinkWithExtraQuery', await client.probe(`${copiedLink}&cacheNonce=${randomUUID()}`, files.original));
  check((await client.probe(siblingLink, files.sibling)).matchesFixture, 'sibling preserved');
  if (state.mode === 'integrated') {
    const retired = await retireFixture(state, client, report);
    check(retired?.state === 'retired' && retired.pending === 0 && retired.completed === 1, 'integrated retirement completed');
    const rows = (await request(`/rest/v1/memory_photos?id=eq.${state.photos[0]}&select=id,path`)).data;
    check(rows?.length === 1 && rows[0].id === state.photos[0], 'exact integrated attachment');
    const newPath = rows[0].path;
    moveRequest({ id: report, bucket: 'vault_photos', source: files.original, destination: newPath });
    const hiddenNew = await request(`/storage/v1/object/sign/vault_photos/${newPath}`, {
      method: 'POST', token: viewer, body: { expiresIn: 3600 }, allowError: true,
    });
    check([400, 401, 403, 404].includes(hiddenNew.status) && !hiddenNew.data?.signedURL, 'hidden moved signing denied');
    const samples = [], started = Date.now();
    for (let elapsed = 0; elapsed <= 75; elapsed += 5) {
      const sample = { elapsedSeconds: Number(((Date.now() - started) / 1000).toFixed(2)),
        waitedSeconds: elapsed, ...await client.probe(copiedLink, files.original) };
      samples.push(sample);
      if ([400, 401, 403, 404, 410].includes(sample.status)) break;
      if (elapsed < 75) await sleep(5000);
    }
    await record('integratedOldLink', samples);
    check([400, 401, 403, 404, 410].includes(samples.at(-1).status), 'integrated old link denied within window');
    await act('restore');
    check((await client.probe(await sign(newPath), newPath)).matchesFixture, 'integrated restored photo bytes');
    check([400, 401, 403, 404, 410].includes((await client.probe(copiedLink, files.original)).status), 'restore never reactivates old link');
    check((await client.probe(siblingLink, files.sibling)).matchesFixture, 'integrated sibling preserved');
    await record('integratedRetirement', { oldLinkDenied: true, hiddenNewSigningDenied: true,
      atomicReferenceRewrite: true, restoredSameBytesAtNewAddress: true, siblingPreserved: true });
    state.complete = true; await save(); return;
  }
  await act('restore');
  check((await client.probe(await sign(files.original), files.original)).matchesFixture, 'restore before relocation');
  await record('hideRestore', { hiddenMemoryDenied: true, hiddenSigningDenied: true, siblingPreserved: true, restored: true });

  // Owner-authorized relocation isolates CDN behavior from service-role ownership.
  // It is NOT an implementation of moderator-side hide/retire/restore.
  await request('/storage/v1/object/move', { method: 'POST', token: owner,
    body: { bucketId: 'vault_photos', sourceKey: files.original, destinationKey: files.retired } });
  const rewritten = (await request(`/rest/v1/memory_photos?id=eq.${state.photos[0]}`, {
    method: 'PATCH', token: owner, body: { path: files.retired },
  })).data;
  check(rewritten?.length === 1 && rewritten[0].id === state.photos[0]
    && rewritten[0].path === files.retired, 'exact attachment reference rewritten');
  check((await client.probe(await sign(files.retired), files.retired)).matchesFixture, 'relocated photo bytes and family access');
  const samples = [], started = Date.now();
  for (let elapsed = 0; elapsed <= 75; elapsed += 5) {
    const sample = { elapsedSeconds: Number(((Date.now() - started) / 1000).toFixed(2)),
      waitedSeconds: elapsed, ...await client.probe(copiedLink, files.original) };
    samples.push(sample);
    if ([400, 401, 403, 404, 410].includes(sample.status)) break;
    if (elapsed < 75) await sleep(5000);
  }
  await record('oldLinkAfterOwnerMove', samples);
  await record('relocation', { newFamilyLinkWorks: true,
    oldLinkDeniedWithinWindow: [400, 401, 403, 404, 410].includes(samples.at(-1).status) });

  await request(`/storage/v1/object/vault_photos/${files.adminSource}`, { method: 'POST', token: owner, bytes: png });
  const scope = path => rpc('media_object_matches_scope', { p_bucket: 'vault_photos', p_path: path,
    p_family: state.family, p_vault: state.vault, p_legacy: null, p_memory: state.memories[0] });
  check(await scope(files.adminSource) === true, 'owner binding before admin move');
  await request('/storage/v1/object/move', { method: 'POST', body: {
    bucketId: 'vault_photos', sourceKey: files.adminSource, destinationKey: files.adminTarget,
  } });
  await record('adminMove', { sourceScopeMatchedBefore: true, destinationScopeMatchesAfter: await scope(files.adminTarget) });
  state.complete = true; await save();
}

async function main(args) {
  if (!['--run', '--run-integrated', '--cleanup'].includes(args[0]) || (args[0] === '--cleanup' ? args.length !== 2 : args.length !== 1)) {
    console.log('Opt-in disposable media-link QA. No production policy or app change.\n'
      + 'HEIRO_RUN_MEDIA_QA=1 node supabase/verification/media_link_live_qa.mjs --run\n'
      + 'HEIRO_RUN_MEDIA_QA=1 node supabase/verification/media_link_live_qa.mjs --run-integrated\n'
      + 'HEIRO_RUN_MEDIA_QA=1 node supabase/verification/media_link_live_qa.mjs --cleanup /private/tmp/heiro-media-qa-RUN.json');
    return;
  }
  check(process.env.HEIRO_RUN_MEDIA_QA === '1', 'explicit live opt-in required');
  const state = args[0] === '--cleanup' ? validateState(JSON.parse(await readFile(args[1], 'utf8')))
    : newState(args[0] === '--run-integrated' ? 'integrated' : 'experiment');
  const path = `/private/tmp/heiro-media-qa-${state.run}.json`;
  if (args[0] === '--cleanup') check(args[1] === path, 'expected cleanup manifest path');
  else await writeFile(path, JSON.stringify(state, null, 2), { mode: 0o600, flag: 'wx' });
  const save = async () => {
    validateState(state);
    await writeFile(`${path}.tmp`, JSON.stringify(state, null, 2), { mode: 0o600 });
    await rename(`${path}.tmp`, path);
  };
  console.log(`Fixture evidence: ${path}`);
  const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '--output', 'json'], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 20000,
  }));
  const admin = keys.find(item => item.name === 'service_role')?.api_key;
  const anon = keys.find(item => item.name === 'anon')?.api_key;
  check(admin && anon, 'authorized server credentials available');
  const client = makeClient({ admin, anon });
  try { if (args[0] !== '--cleanup') await runExperiment(state, client, save); }
  catch (error) {
    // Only our fixed diagnostic labels are persisted, never upstream text.
    state.failure = /^(QA check failed: |QA request failed \(HTTP )/.test(error.message)
      ? error.message : 'Network or unexpected fixture error';
    await save(); throw error;
  }
  finally { await cleanup(state, client, save); }
  console.log('Disposable accounts, family and files removed. Non-content moderation audit may remain.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(error => {
    if (/^(QA check failed: |QA request failed \(HTTP )/.test(error.message)) console.error(error.message);
    else {
      const frame = String(error.stack).split('\n').find(line => /^\s+at /.test(line) && line.includes('media_link_live_qa.mjs:'));
      console.error(`QA diagnostic: ${['TypeError','SyntaxError','RangeError'].includes(error.name) ? error.name : 'unexpected error'}${frame ? ` ${frame.trim()}` : ''}`);
    }
    console.error('Media QA did not finish cleanly. Use its private fixture manifest to inspect results and retry --cleanup. No production fix is confirmed.');
    process.exitCode = 1;
  });
}
