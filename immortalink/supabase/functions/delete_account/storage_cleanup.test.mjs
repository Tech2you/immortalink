import { test } from 'node:test';
import assert from 'node:assert/strict';
import { removeStoragePrefix } from './storage_cleanup.ts';

test('walks every page and nested folder before deleting bounded batches', async () => {
  const removed = [];
  const rows = [...Array.from({length: 1001}, (_, i) => ({id: String(i), name: `file${i}`})), {name: 'nested'}];
  const admin = {storage: {from: () => ({
    list: async (path, {offset, limit}) => ({data: path === 'user' ? rows.slice(offset, offset + limit) : [{id: 'n', name: 'voice'}]}),
    remove: async (paths) => { assert.ok(paths.length <= 100); removed.push(...paths); return {}; },
  })}};
  await removeStoragePrefix(admin, 'photos', 'user');
  assert.equal(new Set(removed).size, 1002);
  assert.ok(removed.includes('user/nested/voice'));
});

test('listing and removal failures do not claim success', async () => {
  for (const stage of ['list', 'remove']) {
    const admin = {storage: {from: () => ({
      list: async () => stage === 'list' ? {error: new Error('denied')} : {data: [{id: '1', name: 'file'}]},
      remove: async () => ({error: new Error('denied')}),
    })}};
    await assert.rejects(removeStoragePrefix(admin, 'photos', 'user'), /denied/);
  }
});

test('empty prefixes cannot wipe a bucket', async () => {
  await assert.rejects(removeStoragePrefix({}, 'photos', '/'), /entire bucket/);
});
