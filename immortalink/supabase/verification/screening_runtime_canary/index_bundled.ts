import configuration from './fixtures.json' with { type: 'json' };
import { createRuntimeCanary } from './runtime_canary.mjs';
import { createBundledNormalizerLoader } from './bundled_normalizer.mjs';
import { createWasmPhotoPreparer } from './photo_wasm.mjs';

const binaryPath = new URL('./magick.wasm', import.meta.url);
const onStage = (stage: string) => console.info(`CANARY_STAGE ${stage}`);
const loadNormalizer = createBundledNormalizerLoader({
  ...configuration.binary,
  // StaticFs supports readFile, not stat for bundled non-npm assets. The
  // operator verifies size before bundling; the loader checks bytes/hash again.
  readBinary: () => Deno.readFile(binaryPath),
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
