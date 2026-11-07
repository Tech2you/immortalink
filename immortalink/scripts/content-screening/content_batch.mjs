import { screenTextOrImage, SCREENING_LIMITS } from '../../supabase/functions/_shared/content_screening.mjs';

// Match PostgreSQL character_length: code points, not UTF-16 code units.
// A 4,000-code-point piece is at most 16 KB of UTF-8, including emoji.
export const CONTENT_BATCH_LIMITS = Object.freeze({ characters: 60000, chunkCharacters: 4000 });

export function textParts(text) {
  if (typeof text !== 'string' || text.length > CONTENT_BATCH_LIMITS.characters * 2) return null;
  const characters = Array.from(text);
  if (characters.length > CONTENT_BATCH_LIMITS.characters) return null;
  const parts = [];
  for (let i = 0; i < characters.length; i += CONTENT_BATCH_LIMITS.chunkCharacters) {
    parts.push(characters.slice(i, i + CONTENT_BATCH_LIMITS.chunkCharacters).join(''));
  }
  return parts.length ? parts : [''];
}

// The DB reserves the entire batch before the first call. No truncated text is
// treated as a complete check; a single failure/flag prevents automatic sharing.
export async function screenContentBatch({ text, images }, options = {}) {
  const parts = textParts(text);
  if (!parts || !Array.isArray(images) || images.length > SCREENING_LIMITS.images) {
    return { state: 'pending', code: 'SOURCE_INVALID', categories: [] };
  }
  const now = options.now ?? Date.now;
  // The provider accepts one photo per request. Pair independent text chunks
  // with individual photos without resending either, and require every result.
  for (let index = 0; index < Math.max(parts.length, images.length); index++) {
    const part = parts[index] ?? '';
    const image = images[index];
    if (options.deadline !== undefined && now() >= options.deadline) {
      return { state: 'pending', code: 'WORKER_DEADLINE', categories: [] };
    }
    // Whitespace-only chunks contain nothing to classify. Their capacity stays
    // reserved; it is never refunded or reused for another request.
    if (!part.trim() && image === undefined) continue;
    const result = await screenTextOrImage({ text: part, images: image === undefined ? [] : [image] }, options);
    if (result.state !== 'clear') return result;
  }
  return { state: 'clear', code: 'SCREENING_CLEAR', categories: [] };
}
