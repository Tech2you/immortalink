import sharp from 'sharp';
import { stillPhotoContainer } from './photo_container.mjs';

// This module belongs in an isolated worker process, not the review web server.
sharp.cache(false);
sharp.concurrency(1);

export const PHOTO_LIMITS = Object.freeze({ inputBytes: 12 * 1024 * 1024,
  pixels: 24_000_000, edge: 2048, outputBytes: 2 * 1024 * 1024, timeoutSeconds: 4 });
const formats = { 'image/jpeg': 'jpeg', 'image/png': 'png', 'image/webp': 'webp' };
const bad = () => new Error('PHOTO_PREPARATION_FAILED');

// Local Node runtime only. No files, external URLs or metadata-preserving option.
// A deployment must enforce process-level memory/CPU limits as well.
export async function preparePhoto(bytes, mime) {
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length > PHOTO_LIMITS.inputBytes ||
      !formats[mime] || !stillPhotoContainer(bytes, mime)) throw bad();
  const input = Buffer.from(bytes);
  const image = sharp(input, { failOn: 'warning', limitInputPixels: PHOTO_LIMITS.pixels,
    sequentialRead: true, animated: false, unlimited: false });
  try {
    const meta = await image.metadata();
    if (meta.format !== formats[mime] || !meta.width || !meta.height ||
        meta.width * meta.height > PHOTO_LIMITS.pixels || (meta.pages ?? 1) !== 1) throw bad();
    // Decode the full image, apply orientation, bound dimensions, strip EXIF/XMP
    // and output one opaque JPEG. Do not silently inspect only an animation frame.
    const output = await image.rotate().resize(PHOTO_LIMITS.edge, PHOTO_LIMITS.edge,
      { fit: 'inside', withoutEnlargement: true }).flatten({ background: '#ffffff' })
      .toColourspace('srgb').jpeg({ quality: 85, chromaSubsampling: '4:4:4' })
      .timeout({ seconds: PHOTO_LIMITS.timeoutSeconds }).toBuffer();
    if (!output.length || output.length > PHOTO_LIMITS.outputBytes) throw bad();
    return { bytes: new Uint8Array(output), mime: 'image/jpeg' };
  } catch { throw bad(); }
  finally { image.destroy(); input.fill(0); }
}
