import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire('/Users/rossstrauss/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=require('playwright');
const server=createServer(async(req,res)=>{try{const name=req.url==='/'?'index.html':req.url.slice(1);if(!/^[a-z.]+$/.test(name))throw Error();res.setHeader('Content-Type',name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'text/html');res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'self'; style-src 'self'; connect-src https://vbzyvaylfdhwowdbodmk.supabase.co; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");res.end(await readFile(new URL('../public/'+name,import.meta.url)));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const url='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const out='/private/tmp/heiro-business-preview';await mkdir(out,{recursive:true});
let report=null;const entries=[];let denied=false;const calls=[];const errors=[];
const page=await browser.newPage({viewport:{width:1440,height:1100}});
page.on('pageerror',e=>errors.push(e.message));
const payload=()=>({current:{accounts:10000,families:1000,paying_contributors:120,funded_families:110,active_production_plans:121,unclassified_plans:1,free_offer_plans:0,storage_bytes:452000000000,storage_objects:150000,excluded_accounts:4,excluded_families:2,new_accounts_30d:80,observed_at:new Date().toISOString()},month:'2026-10-01',report,entries,history:[{day:'2026-10-28',metrics:{accounts:9800}},{day:'2026-10-29',metrics:{accounts:9930}},{day:'2026-10-30',metrics:{accounts:10000}}],exclusions:[]});
await page.route('https://vbzyvaylfdhwowdbodmk.supabase.co/**',async route=>{const req=route.request(),path=new URL(req.url()).pathname;const body=req.postDataJSON();calls.push(path);let result=null,status=200;
if(path.endsWith('/token'))result={access_token:'fake-testing-token',expires_in:3600,user:{email:'owner@example.test',factors:[]}};
else if(path.endsWith('/business_dashboard')){if(denied){status=403;result={message:'BUSINESS_ACCESS_DENIED'};}else result=payload();}
else if(path.endsWith('/business_add_entry')){entries.push({...body.p_entry,created_at:new Date().toISOString()});result=body.p_entry.id;}
else if(path.endsWith('/business_import_proceeds')){entries.push(...body.p_entries.map(e=>({...e,created_at:new Date().toISOString()})));}
else if(path.endsWith('/business_save_report'))report=body.p_report;
else if(path.endsWith('/business_remove_entry'))entries.splice(entries.findIndex(e=>e.id===body.p_id),1);
await route.fulfill({status,contentType:'application/json',body:JSON.stringify(result)});
});
try {
await page.goto(url);await page.screenshot({path:out+'/login.png',fullPage:true});
const signin=async()=>{await page.locator('#email').fill('owner@example.test');await page.locator('#password').fill('dummy-test-password');await page.locator('#login-form button').click();};
await signin();await page.locator('#dashboard-content').waitFor({state:'visible'});assert.equal(await page.locator('#password').inputValue(),'');assert.match(await page.locator('#metrics').innerText(),/10 000|10,000|10 000/);assert.match(await page.locator('#metrics').innerText(),/Not available/);await page.screenshot({path:out+'/overview-desktop.png',fullPage:true});
await page.getByRole('button',{name:'Money & costs',exact:true}).click();await page.locator('#add-entry').click();await page.locator('#entry-form [name="reference"]').fill('<img src=x onerror="window.injected=true">');await page.locator('#entry-form [name="amount"]').fill('25');await page.locator('#entry-form [name="currency"]').fill('USD');await page.locator('#entry-form [name="zar_rate"]').fill('18');await page.getByRole('button',{name:'Save record',exact:true}).click();await page.locator('#entries tr').waitFor();assert.match(await page.locator('#entries').innerText(),/img src/);assert.equal(await page.evaluate(()=>window.injected),undefined);assert.equal(await page.locator('#entries img').count(),0);
await page.locator('#report-form [name="mrr_zar"]').fill('12000');await page.locator('#report-form [name="starting_payers"]').fill('120');await page.locator('#report-form [name="lost_starting_payers"]').fill('4');await page.locator('#report-form [name="reference"]').fill('Test production report');await page.locator('#report-form [name="costs_complete"]').check();await page.getByRole('button',{name:'Save monthly check-in'}).click();await page.waitForFunction(()=>!document.getElementById('dashboard-content').hidden);
await page.getByRole('button',{name:'Import Apple report',exact:true}).click();await page.locator('#apple-file').setInputFiles({name:'report.tsv',mimeType:'text/tab-separated-values',buffer:Buffer.from('Start Date\tEnd Date\tVendor Identifier\tExtended Partner Share\tPartner Share Currency\n10/04/2026\t10/31/2026\teverroots.family.monthly\t250\tUSD')});await page.locator('#import-preview input').fill('18');await page.getByRole('button',{name:'Import proceeds',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('#entries tr').length===2);assert.match(await page.locator('#money-metrics').innerText(),/4.?050/);
await page.screenshot({path:out+'/finances-desktop.png',fullPage:true});await page.locator('#entries button').first().click();await page.getByRole('button',{name:'Keep record',exact:true}).click();assert.equal(entries.length,2);
for(const width of [390,320]){await page.setViewportSize({width,height:844});for(const name of ['Overview','Money & costs','Data & access']){await page.getByRole('button',{name,exact:true}).click();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,`${name} overflow at ${width}`);}await page.getByRole('button',{name:'Overview',exact:true}).click();if(width===390)await page.screenshot({path:out+'/overview-mobile.png',fullPage:true});}
await page.getByRole('button',{name:'Sign out',exact:true}).click();await page.locator('#login').waitFor({state:'visible'});assert.equal(await page.locator('#entries tr').count(),0);assert.equal(await page.evaluate(()=>localStorage.length+sessionStorage.length),0);denied=true;await signin();await page.waitForFunction(()=>document.querySelector('#message').textContent.includes('does not have'));assert.equal(await page.locator('#workspace').isVisible(),false);
assert.deepEqual(errors,[]);assert(calls.includes('/rest/v1/rpc/business_import_proceeds'));console.log('PASS: login, owner denial, ledger, report import, XSS-safe rendering, sign-out, no persisted tokens, mobile 320/390px, desktop and browser errors.');console.log(out);
}finally{await browser.close();server.close();}
