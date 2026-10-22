import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseCommand, runCommand } from './review_content_reports.mjs';
const id = '00000000-0000-4000-8000-000000000001';
const args = ['act', id, 'hide', '--reviewer', 'QA operator', '--notes', 'Reviewed fixture', '--confirm', id];

test('operator commands require an exact report and explicit action confirmation', () => {
  assert.deepEqual(parseCommand([]), { command: 'help' });
  assert.deepEqual(parseCommand(['queue']), { command: 'queue' });
  assert.deepEqual(parseCommand(['health']), { command: 'health' });
  assert.deepEqual(parseCommand(['show', id]), { command: 'show', id });
  assert.equal(parseCommand(args).action, 'hide');
  for (const bad of [args.slice(0, -2), ['act', id, 'delete', ...args.slice(3)],
    ['show', 'all'], ['queue', 'extra'], ['health', 'extra'], [...args.slice(0, -1), 'wrong'],
    ['act', id, 'hide', '--reviewer', 'a', '--reviewer', 'b', '--confirm', id]]) {
    assert.throws(() => parseCommand(bad));
  }
});

test('health uses the read-only operator RPC and preserves warning state', async () => {
  const health = { needs_attention: true, failed: 1 };
  assert.equal(await runCommand(parseCommand(['health']), async (path, body) => {
    assert.equal(path, '/rest/v1/rpc/content_report_alert_health');
    assert.deepEqual(body, {});
    return health;
  }), health);
});

test('queue is bounded and does not include report narrative or media', async () => {
  let path;
  await runCommand(parseCommand(['queue']), async (value) => { path = value; return []; });
  assert.match(path, /limit=50/);
  assert.match(path, /status=in\.\(open,reviewing\)/);
  assert.doesNotMatch(path, /details|reporter_id/);
});

test('moderation uses the audited RPC and verifies its result', async () => {
  const calls = [];
  const result = await runCommand(parseCommand(args), async (path, body) => {
    calls.push({ path, body });
    if (body) return null;
    return [{ id, status: calls.length === 1 ? 'open' : 'resolved', reviewed_at: calls.length === 1 ? null : '2026-10-13T12:00:00Z' }];
  });
  assert.equal(calls.length, 3);
  assert.equal(calls[1].path, '/rest/v1/rpc/review_content_report');
  assert.equal(calls[1].body.p_report_id, id);
  assert.equal(calls[1].body.p_action, 'hide');
  assert.equal(result.status, 'resolved');
});

test('missing report, denied action and ambiguous readback never report success', async () => {
  await assert.rejects(runCommand(parseCommand(args), async () => []), /not found/);
  await assert.rejects(runCommand(parseCommand(args), async (_, body) => {
    if (body) throw new Error('permission denied');
    return [{ id, status: 'open' }];
  }), /permission denied/);
  await assert.rejects(runCommand(parseCommand(args), async (_, body) => body ? null : [{ id, status: 'open' }]), /readback not confirmed/);
});
