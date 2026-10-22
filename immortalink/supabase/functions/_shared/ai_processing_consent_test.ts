import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { hasAiProcessingConsent } from './ai_processing_consent.ts';

Deno.test('only explicit server true permits provider processing', async () => {
  for (const data of [false, null, undefined, 'true', {}, true]) {
    let name = '';
    const allowed = await hasAiProcessingConsent({rpc: async (rpc) => {
      name = rpc;
      return { data, error: null };
    }});
    assertEquals(name, 'has_ai_processing_consent');
    assertEquals(allowed, data === true);
  }
});
Deno.test('a database failure fails closed even with a truthy payload', async () => {
  assertEquals(await hasAiProcessingConsent({rpc: async () => ({data: true, error: {code: 'network'}})}), false);
});
