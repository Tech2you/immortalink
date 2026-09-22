export const MAX_QUESTION_CHARACTERS = 2000;
export const MAX_EMBEDDING_CANDIDATES = 30;
export const MAX_EMBEDDING_PART_CHARACTERS = 1200;

export function boundedEmbeddingCandidates(parts: string[]): string[] {
  return parts.slice(0, MAX_EMBEDDING_CANDIDATES)
    .map((part) => part.slice(0, MAX_EMBEDDING_PART_CHARACTERS));
}
