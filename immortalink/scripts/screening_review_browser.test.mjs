import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {startReviewServer} from './content_review_server.mjs';
import {flagged,queue,preview,decide,ack} from '../supabase/tests/helpers/screening_review_fixture.mjs';
import {deliveryFixture,health} from '../supabase/tests/helpers/delivery_fixture.mjs';
import {memory,viewer,photoPath} from '../supabase/tests/helpers/retirement_fixture.mjs';
import {asUser} from '../supabase/tests/helpers/publication_fixture.mjs';

test('browser and local SQL complete held-image review on desktop/mobile without provider calls',{
  skip:!process.env.PLAYWRIGHT_MODULE,timeout:120000,
},async t=>{
  const {chromium}=await import(process.env.PLAYWRIGHT_MODULE);
  const image=await readFile(new URL('../assets/images/sign_in_logo_heiro.png',import.meta.url));
  const browser=await chromium.launch({headless:true,channel:'chrome'});
  try{
    for(const [name,viewport] of [['desktop',{width:1280,height:900}],['mobile',{width:390,height:844}]])await t.test(name,async()=>{
      const db=await deliveryFixture();let app,page,serial=Promise.resolve();const paths=[],errors=[];
      try{
        await db.query('update memories set body=$1 where id=$2',['<img src=x onerror="window.injected=true">Harmless QA fixture',memory]);
        const id=await flagged(db);
        const backend={request(path,p){
          paths.push(path);
          const operation=serial.then(()=>{
            if(path.endsWith('/content_report_alert_health'))return {needs_attention:false};
            if(path.endsWith('/screening_review_queue'))return queue(db,p.p_state);
            if(path.endsWith('/screening_delivery_health'))return health(db);
            if(path.endsWith('/preview_screening_review'))return preview(db,p.p_case,p.p_reviewer,p.p_media_id,p.p_revision);
            if(path.endsWith('/ack_screening_review_media'))return ack(db,p.p_case,p.p_media_id,p.p_revision,p.p_reviewer);
            if(path.endsWith('/decide_screening_review'))return decide(db,p.p_case,p.p_revision,p.p_action,p.p_reviewer,p.p_notes);
            if(path.endsWith('/content_review_queue'))return [];
            throw new Error(`Unexpected local fixture endpoint: ${path}`);
          });serial=operation.catch(()=>{});return operation;
        },download:async item=>{assert.equal(item.path,photoPath);return image;}};
        app=await startReviewServer({backend,reviewer:'QA',screeningReview:true});
        page=await browser.newPage({viewport});page.setDefaultTimeout(10000);page.on('pageerror',error=>errors.push(error.message));
        page.on('dialog',dialog=>dialog.accept());await page.goto(app.url);
        await page.getByRole('heading',{name:'Automatic checks',exact:true}).waitFor();
        await page.locator('#screening-health').getByText(/Automatic-check delivery checked/).waitFor();
        await page.getByRole('button',{name:/Flagged for human review/}).click();
        await page.getByRole('heading',{name:'Held content',exact:true}).waitFor();
        assert.equal(await page.evaluate(()=>window.injected),undefined);
        assert.equal(await page.locator('.content img').count(),0);
        const approval=page.locator('#screening-action option[value=approve]');
        assert.equal(await approval.evaluate(node=>node.disabled),true);
        await page.getByRole('button',{name:'Show image 1',exact:true}).click();
        await page.waitForFunction(()=>document.querySelector('.attachment img')?.naturalWidth>0);
        assert.equal(await approval.evaluate(node=>node.disabled),false);
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
        await page.screenshot({path:`/private/tmp/heiro-screening-${name}.png`,fullPage:true});
        await page.getByLabel('Check action',{exact:true}).selectOption('hold');
        await page.getByLabel('Decision reason').fill('QA keep private; harmless image.');
        await page.getByLabel('Confirm check reference').fill(id);
        await page.getByRole('button',{name:'Record check decision',exact:true}).click();
        await page.getByText('Check decision recorded: Kept private.',{exact:true}).waitFor();
        assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length,0);
        await page.getByLabel('Check status').selectOption('held');
        await page.getByRole('button',{name:/Flagged for human review/}).click();
        await page.getByRole('button',{name:'Show image 1',exact:true}).click();
        await page.waitForFunction(()=>document.querySelector('.attachment img')?.naturalWidth>0);
        await page.getByLabel('Check action',{exact:true}).selectOption('approve');
        await page.getByLabel('Decision reason').fill('QA approved harmless fixture only.');
        await page.getByLabel('Confirm check reference').fill(id);
        await page.getByRole('button',{name:'Record check decision',exact:true}).scrollIntoViewIfNeeded();
        await page.screenshot({path:`/private/tmp/heiro-screening-${name}-decision.png`});
        await page.getByRole('button',{name:'Record check decision',exact:true}).click();
        await page.getByText('Check decision recorded: Approved.',{exact:true}).waitFor();
        assert.equal((await asUser(db,viewer,'select id from memories where id=$1',[memory])).rows.length,1);
        assert.equal((await health(db)).pending,2);
        assert.equal(await page.getByRole('button',{name:'Record check decision',exact:true}).isDisabled(),true);
        await page.getByLabel('Check status').selectOption('approved');
        await page.getByRole('button',{name:/Flagged for human review/}).click();
        await page.getByRole('heading',{name:'Held content',exact:true}).waitFor();
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
        await db.exec("update content_safety.screening_deliveries set state='uncertain'");
        await page.getByRole('button',{name:'Refresh checks',exact:true}).click();
        await page.locator('#screening-health').getByText(/delivery needs attention/).waitFor();
        await page.screenshot({path:`/private/tmp/heiro-screening-${name}-delivery.png`,fullPage:true});
        assert.equal(paths.some(path=>/review_content_report_checked|retirement|provider|notification/.test(path)),false);
        await page.getByRole('button',{name:'End session',exact:true}).click();
        await page.getByText('Session ended. Close this tab.',{exact:true}).waitFor();
        assert.equal(await page.locator('.attachment').count(),0);
        assert.equal(await page.locator('#screening-panel').isVisible(),false);
        await page.reload();await page.getByText('Session ended. Open Heiro Safety Review.command on your Mac.',{exact:true}).waitFor();
        assert.deepEqual(errors,[]);
      }finally{await page?.close();await app?.close();await serial;await db.close();}
    });
  }finally{await browser.close();}
});
