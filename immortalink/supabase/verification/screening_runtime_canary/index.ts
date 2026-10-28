import configuration from './fixtures.json' with { type: 'json' };
import { createRuntimeCanary, createCanaryNormalizerLoader } from './runtime_canary.mjs';
import { createWasmPhotoPreparer } from './photo_wasm.mjs';

// Fixed stage labels only: never log headers, keys, bodies or error messages.
const onStage = (stage: string) => console.info(`CANARY_STAGE ${stage}`);
const loadNormalizer = createCanaryNormalizerLoader({
  ...configuration.binary,
  createPreparer: createWasmPhotoPreparer,
  onStage,
});
Deno.serve(createRuntimeCanary({
  serviceKeySha256: configuration.serviceKeySha256,
  expiresAt: configuration.expiresAt,
  fixtures: configuration.fixtures,
  loadNormalizer,
  onStage,
}));
