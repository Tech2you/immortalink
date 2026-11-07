import { processScreeningJob } from './worker.mjs';

const json = (status, code) => Response.json({ code }, { status, headers: {
  'cache-control': 'no-store', 'x-content-type-options': 'nosniff',
} });

// Only the database can issue a short-lived, one-use invocation. The HTTP caller
// cannot choose a user, memory, source URL, model, budget or publication result.
/** @param {{enabled?: boolean, backend?: ReturnType<import('./backend.mjs').createScreeningBackend>, apiKey?: string, prepareImage?: Function, fetcher?: typeof fetch, run?: typeof processScreeningJob, waitUntil?: (task: Promise<void>) => void}} options */
export function createScreeningHandler({ enabled = false, backend, apiKey, prepareImage,
  fetcher = fetch, run = processScreeningJob, waitUntil } = {}) {
  return async request => {
    if (!enabled || !backend || !apiKey || typeof prepareImage !== 'function') return json(503, 'SCREENING_DISABLED');
    if (request.method !== 'POST') return json(405, 'METHOD_NOT_ALLOWED');
    const token = request.headers.get('x-screening-run-token');
    if (!token || !/^[a-f0-9]{64}$/.test(token)) return json(401, 'UNAUTHORIZED');
    // No caller body is read or used. Authorization always precedes work.
    try {
      if (await backend.rpc('claim_screening_run', { p_token: token }) !== true) return json(401, 'UNAUTHORIZED');
    } catch { return json(503, 'SCREENING_UNAVAILABLE'); }
    const task = (async () => {
      try { await run({ enabled: true, backend, apiKey, prepareImage, fetcher }); }
      catch { /* The bounded job lease will expire; never log private payloads. */ }
      finally {
        try { await backend.rpc('finish_screening_run', { p_token: token }); }
        catch { /* The cron safety sweep can recover after the run lease. */ }
      }
    })();
    if (typeof waitUntil === 'function') waitUntil(task);
    else await task;
    return json(202, 'SCREENING_ACCEPTED');
  };
}
