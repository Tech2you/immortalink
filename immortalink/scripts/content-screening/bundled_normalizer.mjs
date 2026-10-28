import { createHash } from 'node:crypto';

const fail = () => new Error('BUNDLED_DECODER_UNAVAILABLE');

// The deployment supplies a fixed local asset reader, not an input-controlled
// path or network fallback. One failed initialization stays failed per isolate.
export function createBundledNormalizerLoader({ bytes, sha256, readBinary, createPreparer, onStage = () => {} } = {}) {
  if (!Number.isSafeInteger(bytes) || bytes < 8 || bytes > 20 * 1024 * 1024 ||
      typeof sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(sha256) ||
      typeof readBinary !== 'function' || typeof createPreparer !== 'function' || typeof onStage !== 'function') throw fail();
  const mark = stage => { try { onStage(stage); } catch {} };
  let pending;
  return () => pending ??= (async () => {
    let binary;
    try {
      mark('bundled_binary_read_started');
      binary = await readBinary(bytes);
      if (!(binary instanceof Uint8Array) || binary.length !== bytes ||
          createHash('sha256').update(binary).digest('hex') !== sha256) throw fail();
      mark('bundled_binary_verified');
      const preparer = await createPreparer(binary);
      if (typeof preparer !== 'function') throw fail();
      mark('wasm_init_ready');
      return preparer;
    } catch { throw fail(); }
    finally { if (binary instanceof Uint8Array) binary.fill(0); }
  })();
}
