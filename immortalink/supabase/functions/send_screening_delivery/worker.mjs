import { projectUrl, requestJson, sendDelivery, prepareFirebase } from './transport.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const names = new Set(['claim_screening_delivery', 'authorize_screening_delivery', 'finish_screening_delivery']);
export function makeRpc(serviceKey, fetcher = fetch) {
  return async (name, body) => {
    if (!names.has(name)) throw new Error('RPC_DENIED');
    const response = await requestJson(fetcher, `${projectUrl}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    });
    if (response.status !== 200) throw new Error([401, 403].includes(response.status) ? 'DENIED' : 'DATABASE_UNAVAILABLE');
    return response.data;
  };
}

// The HTTP caller supplies only a one-use invocation, never content, recipients,
// an action or a provider URL. All authority comes from the service-only RPCs.
export function createHandler({ enabled = false, serviceKey, resendKey, firebaseJson,
  fetcher = fetch, now = Date.now, rpc = makeRpc(serviceKey, fetcher), preparePush = prepareFirebase }) {
  const respond = (status, code) => new Response(JSON.stringify({ result: code }), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
  return async request => {
    if (request.method !== 'POST') return respond(405, 'METHOD_NOT_ALLOWED');
    if (enabled !== true) return respond(503, 'DISABLED');
    const token = request.headers.get('x-screening-delivery-token');
    if (!/^[a-f0-9]{64}$/.test(token ?? '')) return respond(401, 'UNAUTHORIZED');
    if (!serviceKey) return respond(503, 'NOT_CONFIGURED');
    let job;
    try { job = await rpc('claim_screening_delivery', { p_token: token }); }
    catch (error) { return respond(error.message === 'DENIED' ? 401 : 503, 'CLAIM_UNAVAILABLE'); }
    if (!uuid.test(job?.id ?? '') || !uuid.test(job?.lease ?? '') || !['email', 'push'].includes(job?.channel)) return respond(503, 'INVALID_JOB');
    let credentials;
    try {
      if (job.channel === 'email') {
        if (!resendKey) throw new Error('NOT_CONFIGURED'); credentials = { resendKey };
      } else credentials = await preparePush(firebaseJson, fetcher, now);
    } catch { return respond(503, 'PROVIDER_UNAVAILABLE'); }
    let grant;
    try { grant = await rpc('authorize_screening_delivery', { p_id: job.id, p_lease: job.lease }); }
    catch { return respond(503, 'AUTHORIZATION_UNAVAILABLE'); }
    if (!grant) return respond(200, 'NOT_ELIGIBLE');
    const deadline = Date.parse(grant.send_before);
    if (grant.id !== job.id || grant.channel !== job.channel || !Number.isFinite(deadline) || deadline <= now() || deadline > now() + 20000 ||
        (job.channel === 'email' ? !uuid.test(grant.case_id ?? '') :
          !uuid.test(grant.family_id ?? '') || !uuid.test(grant.event_id ?? '') || typeof grant.token !== 'string' || !grant.token.length || grant.token.length > 4096)) {
      // Authorization may have committed. Leave the lease for bounded recovery;
      // do not send on an ambiguous or expired grant.
      return respond(503, 'INVALID_GRANT');
    }
    const result = await sendDelivery(grant, credentials, fetcher, now);
    try {
      if (await rpc('finish_screening_delivery', { p_id: job.id, p_lease: job.lease, p_result: result.result, p_retry_seconds: result.retrySeconds }) !== true)
        return respond(503, 'ACK_UNCONFIRMED');
    } catch { return respond(503, 'ACK_UNCONFIRMED'); }
    return respond(result.result === 'ACCEPTED' ? 200 : 503, result.result);
  };
}
