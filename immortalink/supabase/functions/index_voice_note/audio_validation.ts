import { parseBuffer } from "npm:music-metadata@12.0.0";

export const MAX_AUDIO_BYTES = 25 * 1024 * 1024;

export async function validateAudio(bytes: Uint8Array): Promise<{ seconds: number; hash: string }> {
  if (!bytes.length || bytes.length > MAX_AUDIO_BYTES) throw new Error("AUDIO_SIZE_INVALID");
  const metadata = await parseBuffer(bytes, undefined, { duration: true, skipCovers: true });
  const duration = metadata.format.duration;
  if (!duration || !Number.isFinite(duration) || duration <= 0 || duration > 120) {
    throw new Error("AUDIO_DURATION_INVALID");
  }
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return {
    seconds: Math.ceil(duration),
    hash: Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join(""),
  };
}
