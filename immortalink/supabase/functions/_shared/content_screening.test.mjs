import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SCREENING_CATEGORIES, SCREENING_LIMITS, interpretScreeningResponse, screenTextOrImage } from './content_screening.mjs';

const safeBody = () => ({ results: [{ flagged: false,
  categories: Object.fromEntries(SCREENING_CATEGORIES.map((key) => [key, false])),
  category_scores: Object.fromEntries(SCREENING_CATEGORIES.map((key) => [key, 0.01])),
}] });
const json = (value, status = 200) => new Response(JSON.stringify(value), { status });
const configured = (fetcher) => ({ enabled: true, apiKey: 'test-only-key', fetcher });
const png = Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6cDkAAAAASUVORK5CYII='), (c) => c.charCodeAt(0));

test('disabled and missing-key configurations never contact a provider', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; return json(safeBody()); };
  for (const enabled of [undefined, false, 'true', 1]) {
    const result = await screenTextOrImage({ text: 'A family memory.' }, { ...configured(fetcher), enabled });
    assert.equal(result.code, 'SCREENING_DISABLED');
    assert.equal(result.state, 'pending');
  }
  for (const apiKey of [undefined, null, '', '   ']) {
    assert.equal((await screenTextOrImage({ text: 'Memory' }, { ...configured(fetcher), apiKey })).code, 'PROVIDER_NOT_CONFIGURED');
  }
  assert.equal(calls, 0);
});

test('valid text uses a fixed endpoint, model and nonredirecting request', async () => {
  let calls = 0;
  const result = await screenTextOrImage({ text: 'Grandma taught us to cook.' }, configured(async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.openai.com/v1/moderations');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer test-only-key');
    assert.ok(options.signal instanceof AbortSignal);
    assert.deepEqual(JSON.parse(options.body), { model: 'omni-moderation-latest', input: [{ type: 'text', text: 'Grandma taught us to cook.' }] });
    return json(safeBody());
  }));
  assert.deepEqual(result, { state: 'clear', code: 'SCREENING_CLEAR', categories: [] });
  assert.equal(calls, 1);
});

test('photo and caption are checked together using inline bytes, without storage URLs', async () => {
  const result = await screenTextOrImage({ text: 'Family lunch', image: { bytes: png, mime: 'image/png' } }, configured(async (_, options) => {
    const body = JSON.parse(options.body);
    assert.equal(body.input.length, 2);
    assert.equal(body.input[0].text, 'Family lunch');
    assert.match(body.input[1].image_url.url, /^data:image\/png;base64,/);
    assert.deepEqual(Uint8Array.from(atob(body.input[1].image_url.url.split(',')[1]), (c) => c.charCodeAt(0)), png);
    return json(safeBody());
  }));
  assert.equal(result.state, 'clear');
});

test('image-only JPEG, PNG and WebP inputs use their detected MIME type', async () => {
  for (const [bytes, mime] of [[new Uint8Array([255, 216, 255, 224]), 'image/jpeg'], [png, 'image/png'],
    [new TextEncoder().encode('RIFF1234WEBP'), 'image/webp']]) {
    const result = await screenTextOrImage({ image: { bytes, mime } }, configured(async (_, options) => {
      assert.equal(JSON.parse(options.body).input.length, 1);
      assert.ok(JSON.parse(options.body).input[0].image_url.url.startsWith(`data:${mime};base64,`));
      return json(safeBody());
    }));
    assert.equal(result.state, 'clear');
  }
});

test('empty, oversized and unsupported inputs cannot be silently approved or sent', async () => {
  let calls = 0;
  const fetcher = async () => { calls++; return json(safeBody()); };
  const cases = [
    [null, 'INPUT_UNSUPPORTED'], [[], 'INPUT_UNSUPPORTED'], [{}, 'INPUT_EMPTY'],
    [{ text: '  ' }, 'INPUT_EMPTY'], [{ text: 1 }, 'TEXT_INVALID'],
    [{ text: 'x'.repeat(SCREENING_LIMITS.textCharacters + 1) }, 'TEXT_TOO_LARGE'],
    [{ audio: new Uint8Array([1]) }, 'INPUT_UNSUPPORTED'],
    [{ text: 'caption', image: { url: 'http://169.254.169.254/metadata' } }, 'IMAGE_INVALID'],
    [{ text: 'caption', image: { bytes: png, mime: 'image/png', path: 'private/path' } }, 'IMAGE_INVALID'],
    [{ image: { bytes: [], mime: 'image/png' } }, 'IMAGE_INVALID'],
    [{ image: { bytes: new Uint8Array(), mime: 'image/png' } }, 'IMAGE_SIZE_INVALID'],
    [{ image: { bytes: new Uint8Array(SCREENING_LIMITS.imageBytes + 1), mime: 'image/png' } }, 'IMAGE_SIZE_INVALID'],
    [{ image: { bytes: png, mime: 'image/jpeg' } }, 'IMAGE_FORMAT_UNSUPPORTED'],
    [{ image: { bytes: new Uint8Array([1, 2, 3]), mime: 'image/heic' } }, 'IMAGE_FORMAT_UNSUPPORTED'],
  ];
  for (const [input, code] of cases) {
    const result = await screenTextOrImage(input, configured(fetcher));
    assert.equal(result.code, code);
    assert.equal(result.state, 'pending');
  }
  assert.equal(calls, 0);
});

test('boundary-sized text is not silently truncated', async () => {
  const text = 'x'.repeat(SCREENING_LIMITS.textCharacters);
  const result = await screenTextOrImage({ text }, configured(async (_, options) => {
    assert.equal(JSON.parse(options.body).input[0].text, text);
    return json(safeBody());
  }));
  assert.equal(result.state, 'clear');
});

test('a provider flag or a category flag always requires human review', () => {
  for (const flagged of [true, false]) {
    const body = safeBody();
    body.results[0].flagged = flagged;
    body.results[0].categories.violence = true;
    assert.deepEqual(interpretScreeningResponse(body), { state: 'review', code: 'HUMAN_REVIEW_REQUIRED', categories: ['violence'] });
  }
  const body = safeBody(); body.results[0].flagged = true;
  assert.equal(interpretScreeningResponse(body).state, 'review');
});

test('new provider categories cannot bypass a review or leak arbitrary response text', () => {
  const body = safeBody();
  body.results[0].categories['provider-new-category'] = true;
  body.results[0].category_scores['provider-new-category'] = 0.8;
  const result = interpretScreeningResponse(body);
  assert.equal(result.state, 'review');
  assert.deepEqual(result.categories, []);
});

test('incomplete, inconsistent, invalid and multiple-result responses remain pending', () => {
  const mutations = [
    (b) => { b.results = []; }, (b) => { b.results.push(b.results[0]); },
    (b) => { b.results[0].flagged = 'false'; },
    (b) => { delete b.results[0].categories.hate; },
    (b) => { b.results[0].categories.hate = null; },
    (b) => { delete b.results[0].category_scores.hate; },
    (b) => { b.results[0].category_scores.hate = NaN; },
    (b) => { b.results[0].category_scores.hate = Infinity; },
    (b) => { b.results[0].category_scores.hate = 1.1; },
    (b) => { b.results[0].category_scores.hate = -0.1; },
    (b) => { b.results[0].category_scores.hate = '0.1'; },
    (b) => { b.results[0].categories = []; },
    (b) => { b.results[0].category_scores = {}; },
    (b) => { b.results[0] = null; },
  ];
  for (const mutate of mutations) {
    const body = safeBody(); mutate(body);
    assert.equal(interpretScreeningResponse(body).state, 'pending');
  }
  for (const body of [null, {}, [], { results: 'clear' }]) assert.equal(interpretScreeningResponse(body).state, 'pending');
});

test('HTTP failures, malformed JSON and network errors do not leak details or retry', async () => {
  const secret = 'private memory text and API credential';
  for (const status of [301, 302, 307, 400, 401, 403, 404, 409, 422, 429, 500, 503]) {
    let calls = 0;
    const result = await screenTextOrImage({ text: 'Memory' }, configured(async () => { calls++; return json({ error: secret }, status); }));
    assert.equal(result.state, 'pending');
    assert.equal(result.code, status === 429 ? 'PROVIDER_RATE_LIMITED' : 'PROVIDER_UNAVAILABLE');
    assert.equal(JSON.stringify(result).includes(secret), false);
    assert.equal(calls, 1);
  }
  for (const fetcher of [async () => { throw new Error(secret); }, async () => new Response(secret), async () => new Response(null, { status: 204 })]) {
    assert.deepEqual(await screenTextOrImage({ text: 'Memory' }, configured(fetcher)), { state: 'pending', code: 'PROVIDER_UNAVAILABLE', categories: [] });
  }
});

test('oversized provider responses are bounded without trusting Content-Length', async () => {
  let cancelled = false;
  const stream = new ReadableStream({ pull(controller) { controller.enqueue(new Uint8Array(SCREENING_LIMITS.responseBytes + 1)); }, cancel() { cancelled = true; } });
  const result = await screenTextOrImage({ text: 'Memory' }, configured(async () => new Response(stream, { headers: { 'Content-Length': '1' } })));
  assert.equal(result.state, 'pending');
  assert.equal(cancelled, true);
});

test('a stalled response is aborted and never approved', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal;
  const work = screenTextOrImage({ text: 'Memory' }, configured(async (_, options) => { signal = options.signal; return new Promise(() => {}); }));
  t.mock.timers.tick(SCREENING_LIMITS.timeoutMs);
  assert.equal((await work).state, 'pending');
  assert.equal(signal.aborted, true);
});

test('the deadline also covers a response whose headers arrive but body stalls', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let controller;
  let signal;
  const stream = new ReadableStream({ start(value) { controller = value; } });
  const work = screenTextOrImage({ text: 'Memory' }, configured(async (_, options) => {
    signal = options.signal;
    return new Response(stream);
  }));
  await Promise.resolve();
  t.mock.timers.tick(SCREENING_LIMITS.timeoutMs);
  assert.equal((await work).state, 'pending');
  assert.equal(signal.aborted, true);
  controller.close();
});

test('a valid JSON result split across network chunks is read completely', async () => {
  const bytes = new TextEncoder().encode(JSON.stringify(safeBody()));
  const stream = new ReadableStream({ start(controller) {
    for (let i = 0; i < bytes.length; i += 7) controller.enqueue(bytes.subarray(i, i + 7));
    controller.close();
  } });
  assert.equal((await screenTextOrImage({ text: 'Memory' }, configured(async () => new Response(stream)))).state, 'clear');
});
