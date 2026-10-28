const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const projectUrl = 'https://vbzyvaylfdhwowdbodmk.supabase.co';
const oauthUrl = 'https://oauth2.googleapis.com/token';

// Bound both response bodies and elapsed time. Never return provider error text.
export async function requestJson(fetcher, url, init, timeoutMs = 10000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let reader;
  try {
    const response = await fetcher(url, { ...init, redirect: 'error', signal: controller.signal });
    if (Number(response.headers.get('content-length')) > 32768) throw new Error('RESPONSE_LIMIT');
    reader = response.body?.getReader();
    const chunks = []; let length = 0;
    if (reader) for (;;) {
      const { done, value } = await reader.read(); if (done) break;
      length += value.byteLength; if (length > 32768) throw new Error('RESPONSE_LIMIT'); chunks.push(value);
    }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    let data = null;
    try { data = JSON.parse(new TextDecoder().decode(bytes)); } catch { /* An ambiguous success is not acceptance. */ }
    return { status: response.status, data, retryAfter: response.headers.get('retry-after') };
  } finally { clearTimeout(timer); if (reader) await reader.cancel().catch(() => {}); }
}

export function emailPayload(caseId) {
  if (!uuid.test(caseId)) throw new Error('INVALID_CASE');
  return {
    from: 'Heiro Safety <safety@auth.heiro.app>', to: ['linebreakers@outlook.com'], reply_to: 'linebreakers@outlook.com',
    subject: 'Heiro: an automatic check needs review',
    text: `A new shared item is awaiting human review. This is an automatic check, not a user report.\n\nCheck reference: ${caseId}\n\nOn your authorized Mac, open Heiro Safety Review.command and use the enabled Automatic checks section. Paste this reference into Check reference and open it. Keep the Terminal window open. If Automatic checks is unavailable, contact the operator responsible for deployment; do not use the report actions for this check.\n\nNo family names, memory text or attachments are included in this email. Do not forward private content or review-session links. A held item is not automatically deleted. This alert does not mean anyone has reviewed or approved it.`,
    tags: [{ name: 'purpose', value: 'screening_review' }],
  };
}

export function pushPayload(grant) {
  if (!uuid.test(grant.family_id) || !uuid.test(grant.event_id) || typeof grant.token !== 'string' ||
      grant.token.length < 1 || grant.token.length > 4096) throw new Error('INVALID_PUSH');
  return { message: {
    token: grant.token,
    notification: { title: 'A new family memory is available', body: 'Open Heiro to see your family feed.' },
    data: { type: 'family_feed', family_id: grant.family_id, event_id: grant.event_id },
    android: { ttl: '0s', collapse_key: grant.event_id, notification: { tag: grant.event_id } },
    apns: { headers: { 'apns-expiration': '0', 'apns-collapse-id': grant.event_id }, payload: { aps: { sound: 'default' } } },
  } };
}

function backoff(value, now) {
  const seconds = /^\d+$/.test(value ?? '') ? Number(value) : (Date.parse(value ?? '') - now()) / 1000;
  return Math.min(86400, Math.max(60, Number.isFinite(seconds) ? Math.ceil(seconds) : 60));
}
export async function sendDelivery(grant, credentials, fetcher = fetch, now = Date.now) {
  const email = grant.channel === 'email';
  try {
    const response = await requestJson(fetcher, email ? 'https://api.resend.com/emails' :
      `https://fcm.googleapis.com/v1/projects/${credentials.projectId}/messages:send`, {
      method: 'POST', headers: { Authorization: `Bearer ${email ? credentials.resendKey : credentials.accessToken}`,
        'Content-Type': 'application/json', ...(email ? { 'Idempotency-Key': `screening-review/${grant.case_id}/v1` } : {}) },
      body: JSON.stringify(email ? emailPayload(grant.case_id) : pushPayload(grant)),
    });
    if (response.status >= 200 && response.status < 300) {
      const accepted = email ? uuid.test(response.data?.id ?? '') :
        typeof response.data?.name === 'string' && response.data.name.startsWith(`projects/${credentials.projectId}/messages/`) &&
        response.data.name.length > `projects/${credentials.projectId}/messages/`.length;
      return { result: accepted ? 'ACCEPTED' : 'UNKNOWN', retrySeconds: 60 };
    }
    // Only a definite refusal is automatically retried for pushes. A timeout or
    // unparseable success is uncertain and must not cause a second push.
    return { result: response.status === 429 || response.status >= 500 || (email && response.status === 409) ? 'RETRY' : 'REJECTED',
      retrySeconds: backoff(response.retryAfter, now) };
  } catch { return { result: 'UNKNOWN', retrySeconds: 60 }; }
}

function encode(value) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value);
  return btoa(Array.from(bytes, b => String.fromCharCode(b)).join('')).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
export async function prepareFirebase(raw, fetcher = fetch, now = Date.now) {
  if (typeof raw !== 'string' || raw.length > 16384) throw new Error('NOT_CONFIGURED');
  const account = JSON.parse(raw);
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(account.project_id ?? '') ||
      typeof account.client_email !== 'string' || !account.client_email.endsWith(`@${account.project_id}.iam.gserviceaccount.com`) ||
      typeof account.private_key !== 'string') throw new Error('NOT_CONFIGURED');
  const keyBytes = Uint8Array.from(atob(account.private_key.replaceAll('\\n', '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '')), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const seconds = Math.floor(now() / 1000);
  const unsigned = `${encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${encode(JSON.stringify({ iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: oauthUrl, iat: seconds, exp: seconds + 3600 }))}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  const response = await requestJson(fetcher, oauthUrl, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${encode(signature)}` }) });
  if (response.status !== 200 || typeof response.data?.access_token !== 'string' || response.data.access_token.length < 1 ||
      response.data.access_token.length > 8192 || response.data.token_type !== 'Bearer' || !(response.data.expires_in >= 60)) throw new Error('TOKEN_UNAVAILABLE');
  return { projectId: account.project_id, accessToken: response.data.access_token };
}
