import { test } from 'node:test';
import assert from 'node:assert/strict';
import { alertPayload, sendAlert, createHandler } from './worker.mjs';
const report = '00000000-0000-4000-8000-000000000001';
const lease = '00000000-0000-4000-8000-000000000002';
const provider = '00000000-0000-4000-8000-000000000003';
const token = 'a'.repeat(64);
const request = () => new Request('https://worker.test', { method: 'POST', headers: { 'x-report-alert-token': token }, body: JSON.stringify({ to: 'attacker@example.test', report_id: provider }) });
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });

test('payload uses fixed recipients and only a validated report reference', () => {
  const payload = alertPayload(report);
  assert.deepEqual(payload.to, ['linebreakers@outlook.com']);
  assert.equal(payload.from, 'Heiro Safety <safety@auth.heiro.app>');
  assert.equal(payload.subject, 'Heiro: a content report needs review');
  assert.equal(payload.text.includes(report), true);
  assert.equal('attachments' in payload, false);
  assert.equal('html' in payload, false);
  assert.match(payload.text, /Heiro Safety Review\.command/);
  assert.match(payload.text, /Report reference.*Open case/);
  assert.match(payload.text, /not on your phone/);
  assert.doesNotMatch(payload.text, /https?:\/\/|node scripts\/|service_role/);
  assert.throws(() => alertPayload('<script>'), /INVALID_REPORT/);
});

test('retries reuse identical payload and idempotency key', async () => {
  const calls = [];
  const fetcher = async (url, options) => { calls.push({ url, ...options }); return json({ id: provider }); };
  assert.deepEqual(await sendAlert(report, 'test', fetcher), { result: 'ACCEPTED', providerId: provider });
  await sendAlert(report, 'test', fetcher);
  assert.equal(calls[0].body, calls[1].body);
  assert.equal(calls[0].headers['Idempotency-Key'], calls[1].headers['Idempotency-Key']);
});

test('timeouts, transient errors and ambiguous success retry; rejected credentials do not', async () => {
  for (const status of [429, 500, 503, 409]) assert.equal((await sendAlert(report, 'test', async () => json({}, status))).result, 'RETRY');
  for (const status of [400, 401, 403, 422]) assert.equal((await sendAlert(report, 'test', async () => json({}, status))).result, 'REJECTED');
  assert.equal((await sendAlert(report, 'test', async () => { throw new Error('network secret'); })).result, 'RETRY');
  assert.equal((await sendAlert(report, 'test', async () => json({}))).result, 'RETRY');
});

test('worker rejects missing tokens before network and ignores client recipients/content', async () => {
  const calls = [];
  const handler = createHandler({ serviceKey: 'service', resendKey: 'resend', fetcher: async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) });
    if (url.endsWith('claim_content_report_alert')) return json({ report_id: report, lease_id: lease, attempt: 1 });
    if (url === 'https://api.resend.com/emails') return json({ id: provider });
    return json(true);
  } });
  assert.equal((await handler(new Request('https://worker.test', { method: 'POST' }))).status, 401);
  assert.equal(calls.length, 0);
  assert.equal((await handler(request())).status, 200);
  assert.deepEqual(calls[1].body.to, ['linebreakers@outlook.com']);
  assert.equal(calls[1].body.text.includes(report), true);
  assert.equal(calls[2].body.p_lease_id, lease);
  assert.equal(calls[2].body.p_provider_id, provider);
});

test('unauthorized claims, disabled config, idle queue and uncertain ack never claim delivery', async () => {
  assert.equal((await createHandler({ serviceKey: 's' })(request())).status, 503);
  let handler = createHandler({ serviceKey: 's', resendKey: 'r', fetcher: async () => json({}, 403) });
  assert.equal((await handler(request())).status, 401);
  handler = createHandler({ serviceKey: 's', resendKey: 'r', fetcher: async () => json(null) });
  assert.equal((await (await handler(request())).json()).result, 'IDLE');
  for (const ack of [false, null]) {
    handler = createHandler({ serviceKey: 's', resendKey: 'r', fetcher: async (url) => {
      if (url.endsWith('claim_content_report_alert')) return json({ report_id: report, lease_id: lease });
      if (url.endsWith('/emails')) return json({ id: provider });
      return json(ack);
    } });
    assert.equal((await (await handler(request())).json()).result, 'ACK_UNCONFIRMED');
  }
});
