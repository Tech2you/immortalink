import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { startReviewServer } from './content_review_server.mjs';

test('review console renders safely on desktop/mobile and records a deliberate decision',{
  skip:!process.env.PLAYWRIGHT_MODULE,
},async()=>{
  const {chromium}=await import(process.env.PLAYWRIGHT_MODULE);
  const id='00000000-0000-4000-8000-000000000001';
  const mediaId='00000000-0000-4000-8000-000000000002';
  let state='open'; let actions=0;
  const image=await readFile(new URL('../assets/images/sign_in_logo_heiro.png',import.meta.url));
  const backend={
    request:async(path,body)=>{
      if(path.includes('content_report_alert_health'))return {needs_attention:false};
      if(path.includes('review_content_report_checked')){actions++;state='resolved';return {id,action:body.p_action,status:state};}
      if(path.includes('preview_content_report')){
        const media={id:mediaId,kind:'image',bucket:'vault_photos',path:'fixture/logo.png'};
        if(body.p_media_id)return media;
        return {report:{id,kind:'legacy_memory',status:state,reason:'privacy',details:'<img src=x onerror="window.injected=true">',createdAt:'2026-10-18T18:00:00Z',accountActionAvailable:false},
          available:true,fields:{Memory:'Disposable review fixture. No family content is used in this test.'},scopeNote:'Current reported memory and direct attachments only.',revision:(state==='open'?'a':'b').repeat(32),media:[media]};
      }
      return state==='open'?[{id,reason:'privacy',status:state,target_kind:'legacy_memory',created_at:'2026-10-18T18:00:00Z'}]:[];
    },download:async()=>image,
  };
  let browser;
  try{
    browser=await chromium.launch({headless:true,channel:'chrome'});
    for(const [name,viewport] of [['desktop',{width:1280,height:900}],['mobile',{width:390,height:844}]]){
    state='open';actions=0;
    const app=await startReviewServer({backend,reviewer:'QA reviewer'});
    const page=await browser.newPage({viewport});const errors=[];
    try{
    page.setDefaultTimeout(10000);
    page.on('pageerror',(error)=>errors.push(error.message));
    await page.goto(app.url);
    await page.getByText('Private review session ready.',{exact:true}).waitFor();
    assert.equal(new URL(page.url()).hash,'');
    await page.reload();
    await page.getByText('Private review session ready.',{exact:true}).waitFor();
    await page.getByRole('button',{name:/privacy/}).click();
    await page.getByRole('heading',{name:'Current content',exact:true}).waitFor();
    assert.equal(await page.evaluate(()=>window.injected),undefined);
    assert.equal(await page.locator('.statement img').count(),0);
    assert.equal(await page.locator('option[value=suspend]').evaluate((node)=>node.disabled),true);
    await page.getByRole('button',{name:'Show image 1',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.attachment img')?.naturalWidth>0);
    assert.equal(await page.locator('header').count(),1);
    await page.screenshot({path:`/private/tmp/heiro-review-${name}.png`,fullPage:name==='desktop'});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    await page.getByLabel('Action',{exact:true}).selectOption('hide');
    await page.getByLabel('Reason',{exact:true}).fill('Reviewed disposable fixture.');
    await page.getByLabel('Confirm report reference').fill(id);
    await page.getByRole('button',{name:'Record decision',exact:true}).scrollIntoViewIfNeeded();
    await page.screenshot({path:`/private/tmp/heiro-review-${name}-decision.png`});
    await page.getByRole('button',{name:'Record decision',exact:true}).click();
    await page.getByText('No open reports.',{exact:true}).waitFor();assert.equal(actions,1);
    await page.getByRole('button',{name:'End session',exact:true}).click();
    await page.getByText('Session ended. Close this tab.',{exact:true}).waitFor();
    assert.equal(await page.locator('.attachment').count(),0);
    await page.reload();
    await page.getByText('Session ended. Open Heiro Safety Review.command on your Mac.',{exact:true}).waitFor();
    assert.equal(await page.locator('.attachment').count(),0);assert.deepEqual(errors,[]);
    }finally{await page.close();await app.close();}
    }
  }finally{await browser?.close();}
});
