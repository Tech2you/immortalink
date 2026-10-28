import { createHandler } from './worker.mjs';

Deno.serve(createHandler({
  enabled: Deno.env.get('HEIRO_SCREENING_DELIVERIES_ENABLED') === 'true',
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  resendKey: Deno.env.get('HEIRO_REPORT_ALERT_RESEND_API_KEY'),
  firebaseJson: Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON'),
}));
