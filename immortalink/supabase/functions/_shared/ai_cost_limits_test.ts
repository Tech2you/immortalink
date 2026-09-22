import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { boundedEmbeddingCandidates, MAX_QUESTION_CHARACTERS } from './ai_cost_limits.ts';

test('embedding requests have a bounded count and total text size', () => {
  const input = Array.from({ length: 100 }, () => 'x'.repeat(10000));
  const result = boundedEmbeddingCandidates(input);
  assert.equal(result.length, 30);
  assert.equal(result.join('').length, 36000);
  assert.equal(input[0].length, 10000);
});

test('short memory text and order are preserved', () => {
  assert.deepEqual(boundedEmbeddingCandidates(['first', 'second']), ['first', 'second']);
  assert.deepEqual(boundedEmbeddingCandidates([]), []);
  assert.equal(MAX_QUESTION_CHARACTERS, 2000);
});

test('chat reserves usage before paid embeddings and retains output limits', () => {
  const source = readFileSync(new URL('../vault_ai_chat/index.ts', import.meta.url), 'utf8');
  const ranking = source.indexOf('contextParts = await rankContextByMeaning');
  const quota = source.lastIndexOf('const quotaError = await consumeAiUsage', ranking);
  assert.ok(quota >= 0 && quota < ranking);
  assert.match(source.slice(quota, ranking), /if \(quotaError\) return json/);
  assert.match(source, /question.length > MAX_QUESTION_CHARACTERS/);
  assert.match(source, /max_tokens: 220/);
  assert.match(source, /max_tokens: 260/);
});
