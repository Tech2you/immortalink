import { initializeImageMagick, MagickImage, MagickReadSettings, MagickFormat,
  ResourceLimits, AlphaAction, MagickColors, ColorSpace, FilterType } from '@imagemagick/magick-wasm';
import { stillPhotoContainer } from './photo_container.mjs';

// Candidate only: no deploy entrypoint, credentials, filesystem or network.
// Library cache limits are not a replacement for host/isolate memory/CPU limits.
export const WASM_PHOTO_LIMITS = Object.freeze({ inputBytes: 12 * 1024 * 1024,
  pixels: 24_000_000, edge: 1024, outputBytes: 2 * 1024 * 1024,
  cacheBytes: 48 * 1024 * 1024, allocationBytes: 32 * 1024 * 1024, deadlineMs: 800 });
const formats = { 'image/jpeg': MagickFormat.Jpeg, 'image/png': MagickFormat.Png, 'image/webp': MagickFormat.WebP };
const bad = () => new Error('PHOTO_PREPARATION_FAILED');
let initialized;

export async function createWasmPhotoPreparer(wasmBytes) {
  if (!(wasmBytes instanceof Uint8Array) || !wasmBytes.length || wasmBytes.length > 20 * 1024 * 1024) throw bad();
  // Initialize once per isolate using the pinned package's supplied binary only.
  initialized ??= initializeImageMagick(wasmBytes);
  await initialized;
  ResourceLimits.memory = BigInt(WASM_PHOTO_LIMITS.cacheBytes);
  ResourceLimits.maxMemoryRequest = BigInt(WASM_PHOTO_LIMITS.allocationBytes);
  ResourceLimits.disk = 0n;
  ResourceLimits.listLength = 4n;
  ResourceLimits.width = 8192n; ResourceLimits.height = 8192n;
  ResourceLimits.maxProfileSize = 1024n * 1024n;

  return async function preparePhoto(bytes, mime) {
    if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > WASM_PHOTO_LIMITS.inputBytes ||
        !formats[mime] || !stillPhotoContainer(bytes, mime)) throw bad();
    const deadline = performance.now() + WASM_PHOTO_LIMITS.deadlineMs;
    const checkTime = () => { if (performance.now() > deadline) throw bad(); };
    const image = MagickImage.create();
    try {
      image.onWarning = () => { throw bad(); };
      image.onProgress = event => { if (performance.now() > deadline) event.cancel = true; return event.cancel ? 0 : 1; };
      const settings = new MagickReadSettings({ format: formats[mime] });
      image.ping(bytes, settings);
      const width = image.width, height = image.height;
      if (!width || !height || width * height > WASM_PHOTO_LIMITS.pixels || image.format !== formats[mime]) throw bad();
      checkTime();
      // JPEG decoder downsampling avoids allocating the full original pixel map.
      // Do not set a size on small images: libjpeg may otherwise enlarge them.
      if (mime === 'image/jpeg' && Math.max(width, height) > WASM_PHOTO_LIMITS.edge) {
        // libjpeg-turbo rounds hints to eighths. Round up first so the decoder
        // keeps enough detail without allocating a full-size intermediate.
        const scale = Math.min(1, Math.ceil(8 * WASM_PHOTO_LIMITS.edge / Math.max(width, height)) / 8);
        settings.setDefine(MagickFormat.Jpeg, 'size', `${Math.ceil(width * scale)}x${Math.ceil(height * scale)}`);
      }
      image.read(bytes, settings); checkTime();
      image.autoOrient(); checkTime();
      if (Math.max(image.width, image.height) > WASM_PHOTO_LIMITS.edge) {
        image.resize(WASM_PHOTO_LIMITS.edge, WASM_PHOTO_LIMITS.edge, FilterType.Triangle);
      }
      checkTime();
      image.backgroundColor = MagickColors.White; image.alpha(AlphaAction.Remove);
      image.colorSpace = ColorSpace.sRGB; image.strip(); image.quality = 82;
      const output = image.write(MagickFormat.Jpeg, data => {
        checkTime();
        if (!data.length || data.length > WASM_PHOTO_LIMITS.outputBytes) throw bad();
        return new Uint8Array(data);
      });
      return { bytes: output, mime: 'image/jpeg' };
    } catch { throw bad(); }
    finally { image.dispose(); }
  };
}
