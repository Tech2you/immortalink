// Explicitly authorized live QA only. No real account IDs are accepted.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

if (process.env.EVERROOT_RUN_LIVE_QA !== '1') throw new Error('Explicit live QA opt-in required');
const project = 'vbzyvaylfdhwowdbodmk';
const base = `https://${project}.supabase.co`;
const manifestPath = process.env.EVERROOT_QA_MANIFEST || '/tmp/everroots-deletion-qa-state.json';
const state = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8'))
  : { run: randomUUID(), family: randomUUID(), profiles: [randomUUID(), randomUUID()], users: [], steps: {} };
const save = () => writeFileSync(manifestPath, JSON.stringify(state, null, 2), { mode: 0o600 });
save();
if (state.complete) { console.log('QA already completed; see manifest for non-secret evidence.'); process.exit(0); }
const keys = JSON.parse(execFileSync('supabase', ['projects', 'api-keys', '--project-ref', project, '--output', 'json'], { stdio: ['ignore', 'pipe', 'pipe'] }));
const admin = keys.find(k => k.name === 'service_role').api_key;
const anon = keys.find(k => k.name === 'anon').api_key;
const tokens = new Map();
async function request(path, { token = admin, method = 'GET', body, bytes, mime, allowError = false } = {}) {
  const response = await fetch(base + path, { method, headers: {
    apikey: token === admin ? admin : anon, Authorization: `Bearer ${token}`,
    ...(body !== undefined ? { 'Content-Type': 'application/json', Prefer: 'return=representation' } : {}),
    ...(bytes ? { 'Content-Type': mime } : {}),
  }, body: bytes ?? (body === undefined ? undefined : JSON.stringify(body)), signal: AbortSignal.timeout(60000) });
  const raw = await response.text();
  let data; try { data = JSON.parse(raw); } catch { data = raw; }
  if (!response.ok && !allowError) throw new Error(`${method} ${path}: ${response.status} ${JSON.stringify(data)}`);
  return { status: response.status, ok: response.ok, data };
}
async function once(name, action) {
  if (Object.hasOwn(state.steps, name)) return state.steps[name];
  const result = await action(); state.steps[name] = result ?? true; save(); console.log(`PASS ${name}`); return result;
}
const insert = async (table, body, token = admin) => (await request(`/rest/v1/${table}`, { method: 'POST', body, token })).data;
const rows = async (table, filter, token = admin) => (await request(`/rest/v1/${table}?${filter}`, { token })).data;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jFuoAAAAASUVORK5CYII=', 'base64');
const wav = Buffer.alloc(1644);
wav.write('RIFF'); wav.writeUInt32LE(1636, 4); wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22); wav.writeUInt32LE(8000, 24);
wav.writeUInt32LE(16000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(1600, 40);
async function upload(bucket, path, token, data = png, mime = 'image/png') {
  await request(`/storage/v1/object/${bucket}/${path}`, { token, method: 'POST', bytes: data, mime });
}
async function download(bucket, path, token, expected) {
  const r = await fetch(`${base}/storage/v1/object/authenticated/${bucket}/${path}`, {
    headers: { apikey: anon, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30000),
  });
  assert.equal(r.ok, true, `Cannot read ${bucket}/${path}: ${r.status}`);
  assert.deepEqual(Buffer.from(await r.arrayBuffer()), expected, 'File bytes changed');
}
async function denied(bucket, path, token) {
  // Check a new authorized read at origin, separately from previously cached
  // URLs. Supabase documents cacheNonce for bypassing the CDN cache.
  const r = await fetch(`${base}/storage/v1/object/authenticated/${bucket}/${path}?cacheNonce=${randomUUID()}`, {
    headers: { apikey: anon, Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30000),
  });
  await r.arrayBuffer(); assert.equal(r.ok, false, `Private QA media unexpectedly readable: ${bucket}/${path}; status ${r.status}; cache ${r.headers.get('cf-cache-status')}`);
}

try {
  for (let i = 0; i < 3; i++) {
    if (!state.users[i]) {
      const email = `er-deletion-qa-${state.run}-${i}@example.invalid`;
      const password = randomBytes(32).toString('base64url') + 'aA1!';
      const { data } = await request('/auth/v1/admin/users', { method: 'POST', body: { email, password, email_confirm: true } });
      state.users[i] = { id: data.id, email, vault: randomUUID() }; save();
    }
    const user = state.users[i];
    assert.equal(user.email, `er-deletion-qa-${state.run}-${i}@example.invalid`);
    if (state.steps[`delete_user_${i}`]) continue;
    const current = (await request(`/auth/v1/admin/users/${user.id}`)).data;
    assert.equal(current.email, user.email, 'Refusing to operate on a non-fixture account');
    const password = randomBytes(32).toString('base64url') + 'aA1!';
    await request(`/auth/v1/admin/users/${user.id}`, { method: 'PUT', body: { password } });
    const auth = (await request('/auth/v1/token?grant_type=password', { token: anon, method: 'POST', body: { email: user.email, password } })).data;
    tokens.set(user.id, auth.access_token);
  }
  const [a, b, outsider] = state.users;
  const tokenA = tokens.get(a.id), tokenB = tokens.get(b.id), tokenOutside = tokens.get(outsider.id);
  await once('create_isolated_family', () => insert('family_groups', { id: state.family, name: 'Disposable deletion QA', created_by: a.id }));
  for (const [i, user] of [a, b].entries()) {
    await once(`membership_${i}`, () => insert('family_members', { family_id: state.family, user_id: user.id, role: i === 0 ? 'owner' : 'member', is_primary: true }));
    await once(`private_vault_${i}`, () => insert('vaults', { id: user.vault, owner_id: user.id, family_id: state.family, name: 'Disposable QA private vault' }));
    await once(`private_file_${i}`, () => upload('vault_photos', `${user.id}/${user.vault}/private.png`, tokens.get(user.id)));
    await once(`avatar_file_${i}`, () => upload('avatars', `${user.id}/${user.vault}/avatar.png`, tokens.get(user.id)));
  }
  await once('avatars_are_family_scoped', async () => {
    const avatar = `${a.id}/${a.vault}/avatar.png`;
    await download('avatars', avatar, tokenA, png);
    await download('avatars', avatar, tokenB, png);
    await denied('avatars', avatar, tokenOutside);
  });
  await once('family_avatar', () => upload('family_avatars', `${state.family}/avatar`, tokenA));
  await once('outsider_private_vault', () => insert('vaults', { id: outsider.vault, owner_id: outsider.id, name: 'Disposable outsider vault' }));
  const privatePath = `${outsider.id}/${outsider.vault}/private.png`;
  await once('outsider_private_file', () => upload('vault_photos', privatePath, tokenOutside));
  for (let p = 0; p < 2; p++) {
    const creator = [a, b][p], profile = state.profiles[p];
    await once(`legacy_profile_${p}`, () => insert('legacy_family_members', { id: profile, family_id: state.family, name: 'QA Grandma', created_by: creator.id }, tokens.get(creator.id)));
    for (const [i, user] of [a, b].entries()) {
      const path = `${user.id}/${state.family}/legacy/${profile}/gallery/qa.png`;
      await once(`gallery_file_${p}_${i}`, () => upload('vault_photos', path, tokens.get(user.id)));
      await once(`gallery_row_${p}_${i}`, () => insert('legacy_member_photos', { family_id: state.family, legacy_member_id: profile, path }, tokens.get(user.id)));
      const memory = await once(`story_${p}_${i}`, async () => (await insert('legacy_memories', {
        legacy_member_id: profile, family_id: state.family, life_stage: 'early', prompt_key: 'legacy_memory',
        prompt_text: 'Disposable QA', body: `Contribution ${i} to profile ${p}`,
      }, tokens.get(user.id)))[0].id);
      const voicePath = `${user.id}/${state.family}/legacy/${profile}/memories/${memory}/voice/qa.wav`;
      await once(`voice_file_${p}_${i}`, () => upload('memory_voice', voicePath, tokens.get(user.id), wav, 'audio/wav'));
      await once(`voice_row_${p}_${i}`, () => insert('legacy_memory_voice_notes', { family_id: state.family, legacy_member_id: profile, legacy_memory_id: memory, path: voicePath }, tokens.get(user.id)));
    }
  }
  await once('forged_media_references_denied', async () => {
    const body = { family_id: state.family, legacy_member_id: state.profiles[0], path: privatePath };
    const forged = await request('/rest/v1/legacy_member_photos', { token: tokenA, method: 'POST', body, allowError: true });
    assert.equal(forged.status, 403);
    assert.match(forged.data.message, /MEDIA_OBJECT_SCOPE_MISMATCH/);
    const photos = await rows('legacy_member_photos', `family_id=eq.${state.family}`, tokenA);
    const changed = await request(`/rest/v1/legacy_member_photos?id=eq.${photos[0].id}`, {
      token: tokenA, method: 'PATCH', body: { path: privatePath }, allowError: true,
    });
    assert.equal(changed.status, 403);
    // Simulate a historical bad metadata row using only a disposable private file.
    const historical = (await insert('legacy_member_photos', body))[0];
    await denied('vault_photos', privatePath, tokenA);
    await request(`/rest/v1/legacy_member_photos?id=eq.${historical.id}`, { method: 'DELETE' });
  });
  if (process.env.EVERROOT_TRANSCRIPTION_QA_AUDIO) {
    await once('live_transcription_consent_scope_and_idempotency', async () => {
      const recording = (await rows('legacy_memory_voice_notes', `family_id=eq.${state.family}`, tokenA))[0];
      const payload = { legacy_memory_voice_note_id: recording.id };
      const noConsent = await request('/functions/v1/index_voice_note', { token: tokenA, method: 'POST', body: payload, allowError: true });
      assert.equal(noConsent.status, 403);
      assert.equal(noConsent.data.code, 'AI_CONSENT_REQUIRED');
      await request('/rest/v1/rpc/set_ai_processing_consent', { token: tokenA, method: 'POST', body: { p_allowed: true } });
      const audio = readFileSync(process.env.EVERROOT_TRANSCRIPTION_QA_AUDIO);
      const audioPath = `${a.id}/${state.family}/legacy/${recording.legacy_member_id}/memories/${recording.legacy_memory_id}/voice/speech.m4a`;
      await upload('memory_voice', audioPath, tokenA, audio, 'audio/mp4');
      const voice = (await insert('legacy_memory_voice_notes', {
        family_id: state.family, legacy_member_id: recording.legacy_member_id,
        legacy_memory_id: recording.legacy_memory_id, path: audioPath,
        duration_seconds: 1,
      }, tokenA))[0];
      const validPayload = { legacy_memory_voice_note_id: voice.id };
      for (let repeat = 0; repeat < 2; repeat++) {
        const result = await request('/functions/v1/index_voice_note', { token: tokenA, method: 'POST', body: validPayload });
        assert.equal(result.data.ok, true);
      }
      const jobs = await rows('voice_transcription_jobs', `scope_id=eq.${state.family}`);
      assert.equal(jobs.length, 1);
      assert.equal(jobs[0].status, 'succeeded');
      assert.ok(jobs[0].seconds > 1, 'Client duration must not control quota');
      const saved = (await rows('legacy_memory_voice_notes', `id=eq.${voice.id}`, tokenA))[0];
      assert.ok(saved.transcript.length > 0);
      await request('/rest/v1/rpc/set_ai_processing_consent', { token: tokenA, method: 'POST', body: { p_allowed: false } });
      const withdrawn = await request('/functions/v1/index_voice_note', { token: tokenA, method: 'POST', body: validPayload, allowError: true });
      assert.equal(withdrawn.status, 403);
      // Keep the original deletion fixture's exact four-recording assertions.
      await request(`/rest/v1/legacy_memory_voice_notes?id=eq.${voice.id}`, { method: 'DELETE' });
    });
  }
  async function deleteFixture(i) {
    const user = state.users[i];
    await once(`delete_user_${i}`, async () => {
      const r = await request('/functions/v1/delete_account', { token: tokens.get(user.id), method: 'POST', body: {} });
      assert.equal(r.data.ok, true);
      const deleted = await request(`/auth/v1/admin/users/${user.id}`, { allowError: true });
      assert.equal(deleted.status, 404, 'Auth account was not removed');
    });
  }
  await once('before_deletion_access', async () => {
    const photos = await rows('legacy_member_photos', `family_id=eq.${state.family}`, tokenB);
    assert.equal(photos.length, 4);
    for (const photo of photos) await download('vault_photos', photo.path, tokenB, png);
    await denied('vault_photos', photos[0].path, tokenOutside);
  });
  if (process.env.EVERROOT_SAFETY_QA === '1') {
    await once('safety_report_block_and_moderation', async () => {
      const rpc = (name, body, token, allowError = false) => request(`/rest/v1/rpc/${name}`, { method: 'POST', body, token, allowError });
      for (const prior of state.safetyReports ?? []) {
        const saved = (await rows('content_reports', `id=eq.${prior}`))[0];
        assert.equal(saved.details, `Disposable safety QA ${state.run}`, 'Only fixture reviews may be reset');
        for (const action of ['restore', 'reinstate']) {
          await rpc('review_content_report', { p_report_id: prior, p_action: action,
            p_reviewer: 'Disposable QA operator', p_notes: `Resume disposable safety QA ${state.run}` }, admin);
        }
      }
      // Reset only this fixture's preference after an interrupted QA attempt.
      await rpc('set_member_block', { p_member_id: a.id, p_blocked: false }, tokenB);
      const reportBody = { p_kind: 'vault', p_target_id: a.vault, p_reason: 'other', p_details: `Disposable safety QA ${state.run}` };
      const report = (await rpc('report_family_content', reportBody, tokenB)).data;
      state.safetyReports = [...new Set([...(state.safetyReports ?? []), report])]; save();
      assert.equal((await rpc('report_family_content', reportBody, tokenB)).data, report);
      assert.equal((await rows('content_reports', `id=eq.${report}`, tokenA)).length, 0);
      assert.equal((await rpc('report_family_content', { ...reportBody, p_target_id: outsider.vault }, tokenB, true)).status, 403);
      assert.equal((await rpc('review_content_report', { p_report_id: report, p_action: 'hide', p_reviewer: 'forged', p_notes: 'forged' }, tokenB, true)).ok, false, 'Client must not moderate');
      const galleryPath = `${a.id}/${state.family}/legacy/${state.profiles[0]}/gallery/qa.png`;
      await download('vault_photos', galleryPath, tokenB, png);
      await rpc('set_member_block', { p_member_id: a.id, p_blocked: true }, tokenB);
      assert.equal((await rows('vaults', `id=eq.${a.vault}`, tokenB)).length, 0);
      assert.equal((await rows('vaults', `id=eq.${b.vault}`, tokenA)).length, 0);
      assert.equal((await rows('legacy_memories', `family_id=eq.${state.family}`, tokenB)).length, 2);
      assert.equal((await rpc('read_shared_vault_media', { p_vault_id: a.vault }, tokenB, true)).status, 403);
      await denied('vault_photos', `${a.id}/${a.vault}/private.png`, tokenB);
      await denied('vault_photos', galleryPath, tokenB);
      const signed = await request(`/storage/v1/object/sign/vault_photos/${galleryPath}`, { token: tokenB, method: 'POST', body: { expiresIn: 60 }, allowError: true });
      assert.equal(signed.ok, false, 'A blocked member must not receive a new signed URL');
      const cached = await fetch(`${base}/storage/v1/object/authenticated/vault_photos/${galleryPath}`, { headers: { apikey: anon, Authorization: `Bearer ${tokenB}` }, signal: AbortSignal.timeout(30000) });
      await cached.arrayBuffer();
      state.safetyCacheEvidence = { status: cached.status, cache: cached.headers.get('cf-cache-status'), cacheControl: cached.headers.get('cache-control') }; save();
      await rpc('set_member_block', { p_member_id: a.id, p_blocked: false }, tokenB);
      assert.equal((await rows('legacy_memories', `family_id=eq.${state.family}`, tokenB)).length, 4);
      await download('vault_photos', `${a.id}/${a.vault}/private.png`, tokenB, png);
      const stories = await rows('legacy_memories', `family_id=eq.${state.family}&contributor_id=eq.${a.id}`, tokenB);
      assert.equal(stories.length, 2);
      const storyReport = (await rpc('report_family_content', { ...reportBody, p_kind: 'legacy_memory', p_target_id: stories[0].id }, tokenB)).data;
      state.safetyReports = [...new Set([...state.safetyReports, storyReport])]; save();
      const reviewBody = { p_report_id: storyReport, p_action: 'hide', p_reviewer: 'Disposable QA operator', p_notes: `Disposable safety QA ${state.run}` };
      await rpc('review_content_report', reviewBody, admin);
      assert.equal((await rows('legacy_memories', `id=eq.${stories[0].id}`, tokenB)).length, 0);
      assert.equal((await rows('legacy_memory_voice_notes', `legacy_memory_id=eq.${stories[0].id}`, tokenB)).length, 0);
      await rpc('review_content_report', { ...reviewBody, p_action: 'restore' }, admin);
      assert.equal((await rows('legacy_memories', `id=eq.${stories[0].id}`, tokenB)).length, 1);
      await rpc('review_content_report', { ...reviewBody, p_report_id: report, p_action: 'suspend' }, admin);
      const suspendedEdit = await request(`/rest/v1/legacy_memories?id=eq.${stories[0].id}`, { method: 'PATCH', token: tokenA, body: { body: 'Should be denied' }, allowError: true });
      assert.ok(!suspendedEdit.ok || (Array.isArray(suspendedEdit.data) && suspendedEdit.data.length === 0), 'Suspended edit must fail or affect zero rows');
      assert.notEqual((await rows('legacy_memories', `id=eq.${stories[0].id}`))[0].body, 'Should be denied');
      await rpc('review_content_report', { ...reviewBody, p_report_id: report, p_action: 'reinstate' }, admin);
      assert.equal((await rows('legacy_memories', `family_id=eq.${state.family}`, tokenB)).length, 4);
    });
  }
  await deleteFixture(0);
  await once('shared_content_and_survivor_verified', async () => {
    const profiles = await rows('legacy_family_members', `family_id=eq.${state.family}`, tokenB);
    assert.equal(profiles.length, 2); assert.ok(profiles.every(p => p.created_by === b.id));
    const photos = await rows('legacy_member_photos', `family_id=eq.${state.family}`, tokenB);
    const stories = await rows('legacy_memories', `family_id=eq.${state.family}`, tokenB);
    const voices = await rows('legacy_memory_voice_notes', `family_id=eq.${state.family}`, tokenB);
    assert.equal(photos.length, 4); assert.equal(stories.length, 4); assert.equal(voices.length, 4);
    for (const photo of photos) { await download('vault_photos', photo.path, tokenB, png); await denied('vault_photos', photo.path, tokenOutside); }
    for (const voice of voices) await download('memory_voice', voice.path, tokenB, wav);
    await download('family_avatars', `${state.family}/avatar`, tokenB, png);
    await download('vault_photos', `${b.id}/${b.vault}/private.png`, tokenB, png);
    assert.equal((await rows('vaults', `id=eq.${a.vault}`)).length, 0);
    await denied('vault_photos', `${a.id}/${a.vault}/private.png`, tokenB);
    assert.equal((await rows('family_members', `family_id=eq.${state.family}`))[0].role, 'owner');
  });
  await once('survivor_can_still_contribute', async () => {
    const path = `${b.id}/${state.family}/legacy/${state.profiles[0]}/gallery/after.png`;
    await upload('vault_photos', path, tokenB);
    await insert('legacy_member_photos', { family_id: state.family, legacy_member_id: state.profiles[0], path }, tokenB);
    await download('vault_photos', path, tokenB, png);
  });
  await deleteFixture(1);
  await deleteFixture(2);
  await once('last_member_and_jobs_cleaned', async () => {
    assert.equal((await rows('family_groups', `id=eq.${state.family}`)).length, 0);
    assert.equal((await rows('legacy_family_members', `family_id=eq.${state.family}`)).length, 0);
    for (const user of state.users) assert.equal((await rows('account_deletion_jobs', `user_id=eq.${user.id}`)).length, 0);
  });
  state.complete = true; save(); console.log(JSON.stringify({ complete: true, run: state.run, family: state.family, users: state.users.map(u => u.id) }));
} catch (error) {
  console.error(`QA STOPPED: ${error.message}`);
  console.error(`Fixture IDs (no credentials): ${manifestPath}. Fix before resuming; no existing users were selected.`);
  process.exitCode = 1;
}
