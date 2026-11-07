import { createHash } from 'node:crypto';
import { createScreeningBackend } from '../../../scripts/content-screening/backend.mjs';
import { createRemotePhotoPreparer } from '../../../scripts/content-screening/photo_transport.mjs';
import { createScreeningHandler } from '../../../scripts/content-screening/worker_transport.mjs';

declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

const enabled = Deno.env.get('HEIRO_CONTENT_SCREENING_ENABLED') === 'true';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const apiKey = Deno.env.get('OPENAI_API_KEY');
// Domain-separated secret is never sent to clients or stored in pg_net logs.
const workerToken = serviceKey ? createHash('sha256').update(`heiro-screening-photo:${serviceKey}`).digest('hex') : '';
Deno.serve(createScreeningHandler({
  enabled, apiKey,
  backend: serviceKey ? createScreeningBackend({ serviceKey }) : undefined,
  prepareImage: serviceKey ? createRemotePhotoPreparer({ gatewayKey: serviceKey, workerToken }) : undefined,
  waitUntil: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
}));
