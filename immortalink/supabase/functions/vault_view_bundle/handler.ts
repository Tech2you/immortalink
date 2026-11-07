// Retired: this legacy service-role bundle bypassed per-memory sharing/blocking.
// Current clients use caller-authorized queries and private Storage policies.
// Keep a tombstone so an old deployment cannot silently remain reachable.
export function handleRetiredVaultBundle(req: Request): Response {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Content-Type": "application/json",
  };
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  return new Response(JSON.stringify({
    error: "ENDPOINT_RETIRED",
    message: "This older media endpoint is no longer available. Please update Heiro.",
  }), { status: 410, headers });
}

