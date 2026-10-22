import { createHandler } from './worker.mjs';

Deno.serve(createHandler({
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  resendKey: Deno.env.get('HEIRO_REPORT_ALERT_RESEND_API_KEY'),
}));
