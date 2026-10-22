const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const projectUrl = 'https://vbzyvaylfdhwowdbodmk.supabase.co';
const from = 'Heiro Safety <safety@auth.heiro.app>';
const to = 'linebreakers@outlook.com';

export function alertPayload(reportId) {
  if (!uuid.test(reportId)) throw new Error('INVALID_REPORT_ID');
  return {
    from, to: [to], reply_to: to,
    subject: 'Heiro: a content report needs review',
    text: `A content report needs review.\n\nReference: ${reportId}\n\nReview on your authorized Mac:\n1. In Finder, open the Heiro project folder and double-click "Heiro Safety Review.command".\n2. Keep its Terminal window open. The private review page opens in your browser.\n3. Select the report, or paste the reference above into "Report reference" and choose "Open case".\n4. Review the available context, select an action, enter a reason and confirm the reference before choosing "Record decision".\n\nThe review page runs only on that Mac, not on your phone. After 30 minutes, double-click the launcher again for a new session. A Supabase dashboard link is not a report view.\n\nNames, report statements and family media are intentionally excluded from this email. Do not forward private report details, media or the private session link.\nThis alert does not mean the report has been reviewed or content removed.`,
    tags: [{ name: 'purpose', value: 'content_safety' }],
  };
}

export async function sendAlert(reportId, key, fetcher = fetch) {
  try {
    const response = await fetcher('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json',
        'Idempotency-Key': `content-report/${reportId}/v1` },
      body: JSON.stringify(alertPayload(reportId)), signal: AbortSignal.timeout(12000),
    });
    if (response.ok) {
      const body = await response.json();
      return uuid.test(body?.id) ? { result: 'ACCEPTED', providerId: body.id } : { result: 'RETRY' };
    }
    // Never log provider responses: they can echo request fields or credentials.
    return { result: response.status === 429 || response.status >= 500 || response.status === 409 ? 'RETRY' : 'REJECTED' };
  } catch {
    return { result: 'RETRY' };
  }
}

export function createHandler({ serviceKey, resendKey, fetcher = fetch }) {
  const respond = (status, code) => new Response(JSON.stringify({ result: code }), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
  const rpc = async (name, body) => {
    const response = await fetcher(`${projectUrl}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(response.status === 403 ? 'DENIED' : 'DB_UNAVAILABLE');
    return response.json();
  };
  return async (request) => {
    if (request.method !== 'POST') return respond(405, 'METHOD_NOT_ALLOWED');
    const token = request.headers.get('x-report-alert-token');
    if (!token || !/^[a-f0-9]{64}$/.test(token)) return respond(401, 'UNAUTHORIZED');
    if (!serviceKey || !resendKey) return respond(503, 'NOT_CONFIGURED');
    let job;
    try { job = await rpc('claim_content_report_alert', { p_worker_token: token }); }
    catch (error) { return respond(error.message === 'DENIED' ? 401 : 503, 'CLAIM_UNAVAILABLE'); }
    if (!job) return respond(200, 'IDLE');
    if (!uuid.test(job.report_id) || !uuid.test(job.lease_id)) return respond(503, 'INVALID_JOB');
    const sent = await sendAlert(job.report_id, resendKey, fetcher);
    try {
      const finished = await rpc('finish_content_report_alert', {
        p_report_id: job.report_id, p_lease_id: job.lease_id, p_result: sent.result, p_provider_id: sent.providerId ?? null,
      });
      if (finished !== true) return respond(503, 'ACK_UNCONFIRMED');
    } catch { return respond(503, 'ACK_UNCONFIRMED'); }
    return respond(sent.result === 'ACCEPTED' ? 200 : 503, sent.result);
  };
}
