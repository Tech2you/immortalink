import { test } from 'node:test';
import assert from 'node:assert/strict';
import { screenContentBatch, textParts } from './content_batch.mjs';
import { SCREENING_CATEGORIES } from '../../supabase/functions/_shared/content_screening.mjs';
const response = flagged => Response.json({ results: [{ flagged,
  categories: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, false])),
  category_scores: Object.fromEntries(SCREENING_CATEGORIES.map(key => [key, 0.01])),
}] });

test('long Unicode text is preserved exactly and bounded per request', () => {
  const text = '🙂abc漢字'.repeat(9000), parts = textParts(text);
  assert.equal(parts.join(''), text);
  assert(parts.every(part => Array.from(part).length <= 4000 && Buffer.byteLength(part) <= 16000));
  assert.equal(textParts('x'.repeat(60001)), null);
});

test('all text chunks must clear; images are sent only once and late flags stop publication', async () => {
  const text = 'a'.repeat(9000), sent = [];
  const result = await screenContentBatch({ text, images: [{ bytes: Uint8Array.from([255,216,255,224]), mime: 'image/jpeg' }] }, {
    enabled: true, apiKey: 'fake-test-only', fetcher: async (_, init) => {
      sent.push(JSON.parse(init.body)); return response(sent.length === 3);
    },
  });
  assert.equal(result.state, 'review'); assert.equal(sent.length, 3);
  assert.deepEqual(sent.map(body => body.input.filter(x => x.type === 'image_url').length), [1,0,0]);
  assert.equal(sent.flatMap(body => body.input.filter(x => x.type === 'text').map(x => x.text)).join(''), text);
});

test('errors and worker deadlines never clear partially checked content', async () => {
  let calls=0;
  const result=await screenContentBatch({text:'x'.repeat(9000),images:[]},{enabled:true,apiKey:'fake-test-only',
    fetcher:async()=>{calls++;return calls===1?response(false):new Response('',{status:503});}});
  assert.equal(result.state,'pending');assert.equal(calls,2);
  const expired=await screenContentBatch({text:'story',images:[]},{deadline:1,now:()=>2,
    fetcher:async()=>assert.fail('expired work must not call the provider')});
  assert.equal(expired.code,'WORKER_DEADLINE');
});

test('20 distinct photos are each checked once and a late flag or outage never clears the batch', async () => {
  const images=Array.from({length:20},(_,index)=>({bytes:Uint8Array.from([255,216,255,224,index]),mime:'image/jpeg'}));
  for(const outcome of ['clear','late-flag','late-outage']){
    const seen=[];
    const result=await screenContentBatch({text:'A family story',images},{enabled:true,apiKey:'fixture-only',
      fetcher:async(_,init)=>{
        const body=JSON.parse(init.body),photos=body.input.filter(x=>x.type==='image_url');
        assert.equal(photos.length,1);
        const bytes=Buffer.from(photos[0].image_url.url.split(',')[1],'base64');seen.push(bytes.at(-1));
        if(seen.length===20 && outcome==='late-outage')return new Response('',{status:503});
        return response(seen.length===20 && outcome==='late-flag');
      }});
    assert.deepEqual(seen,Array.from({length:20},(_,i)=>i));
    assert.equal(result.state,{clear:'clear','late-flag':'review','late-outage':'pending'}[outcome]);
  }
});
