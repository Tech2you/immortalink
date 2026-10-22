export async function hasAiProcessingConsent(client: {
  rpc: (name: string) => PromiseLike<{ data: unknown; error: unknown }>;
}): Promise<boolean> {
  const { data, error } = await client.rpc('has_ai_processing_consent');
  return !error && data === true;
}
