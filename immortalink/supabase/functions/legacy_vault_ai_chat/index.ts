// Retired in favor of vault_ai_chat, which enforces consent, access and quotas.
Deno.serve((request) => new Response(
  request.method === 'OPTIONS' ? 'ok' : JSON.stringify({
    code: 'UPDATE_REQUIRED',
    error: 'Update Ever Roots to use AI chat with privacy and usage controls.',
  }),
  {
    status: request.method === 'OPTIONS' ? 200 : 410,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    },
  },
));
