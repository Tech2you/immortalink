import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const out = new URL('.', import.meta.url).pathname;
const wb = Workbook.create();
const m = wb.worksheets.add('Model');
const a = wb.worksheets.add('Assumptions');
const val = (s,c,x) => s.getRange(c).values = [[x]];
const f = (s,c,x) => s.getRange(c).formulas = [[x]];
const A = n => `Assumptions!$C$${n}`;
const money = '"R"#,##0.00;("R"#,##0.00);"–"';
const usd = '"$"#,##0.00;("$"#,##0.00);"–"';
const num = '#,##0.00;(#,##0.00);"–"';
for (const s of [m,a]) {
  s.showGridLines = false;
  s.getRange('A1:J100').format.font = {name:'Arial',size:10,color:'#20343D'};
  s.getRange('A1:J100').format.rowHeight = 23;
  s.getRange('A:A').format.columnWidth = 3;
  s.getRange('B:B').format.columnWidth = 42;
  s.getRange('C:I').format.columnWidth = 18;
  s.freezePanes.freezeRows(4);
}
const title = (s,c,t) => {val(s,c,t);s.getRange(c).format.font={name:'Arial',size:16,bold:true,color:'#123D48'};};
const head = (s,r,labels) => {s.getRange(r).values=[labels];s.getRange(r).format={fill:'#E3F1F2',font:{name:'Arial',size:10,bold:true,color:'#174E59'},rowHeight:34,wrapText:true};};
const note = (s,r,t) => {s.getRange(r).merge();s.getRange(r).values=[[t]];s.getRange(r).format={wrapText:true,font:{name:'Arial',size:10,color:'#536770'},rowHeight:40};};
title(a,'B2','HEIRO / EDITABLE ASSUMPTIONS');
note(a,'B3:H3','Planning estimate dated 6 November 2026. Blue values are editable. No service settings or spending caps are changed by this workbook.');
head(a,'B4:E4',['Input','Value','Unit','Basis / source']);
a.getRange('E:E').format.columnWidth=52;
const inputs = [
 [5,'Planning exchange rate',18,'ZAR / USD','Illustrative; replace with your actual conversion rate.'],
 [6,'SA consumer VAT',.15,'%','SARS current VAT rate; Apple collects applicable storefront tax.'],
 [7,'Apple commission',.30,'%','30% conservative first-year assumption; use 15% if approved for Small Business.'],
 [8,'Supplier tax reserve',.15,'%','Conservative allowance on USD costs; confirm actual supplier invoices. Not a verified tax charge.'],
 [9,'Existing free-family original storage',10000,'GB','Scale scenario: about 20,000 families at a nominal 0.5 GB each.'],
 [10,'Paid storage used',1,'% of allowance','100% stress assumption; actual occupied storage is billed, not allocated capacity.'],
 [11,'Backup size / original size',1,'multiple','One full copy. Increase for retained deleted/replaced versions.'],
 [12,'Uncached downloads / stored GB',.1,'GB / GB / month','10% of stored bytes transferred each month; editable traffic assumption.'],
 [13,'Cached downloads / stored GB',0,'GB / GB / month','Separate cached-egress allowance. Actual cache mix is unknown.'],
 [14,'Paid AI allowances used',1,'%','100% of paid answers and transcription allowance.'],
 [15,'Input tokens per answer',4000,'tokens','Planning estimate, not measured production average.'],
 [16,'Output tokens per answer',260,'tokens','Conservative normal response allowance.'],
 [17,'Chat input price',.15,'USD / million tokens','gpt-4o-mini standard pricing.'],
 [18,'Chat output price',.60,'USD / million tokens','gpt-4o-mini standard pricing.'],
 [19,'Transcription price',.003,'USD / minute','Estimated gpt-4o-mini-transcribe usage price.'],
 [20,'Extra AI reserve',60,'USD / month','Reserve for free-family activity, embeddings and retries; not full use by all free families.'],
 [21,'Supabase Pro',25,'USD / month','One Micro project included.'],
 [22,'Supabase included storage',100,'GB','Pro allowance.'],
 [23,'Supabase extra storage',.0213,'USD / GB-month','Average occupied storage; monthly approximation.'],
 [24,'R2 included Standard storage',10,'GB-month','Free tier; assumes no other bucket uses this allowance.'],
 [25,'R2 extra Standard storage',.015,'USD / GB-month','R2 Standard; rounded-up GB-month estimate.'],
 [26,'Included uncached egress',250,'GB / month','Supabase Pro allowance.'],
 [27,'Extra uncached egress',.09,'USD / GB','Supabase Pro overage.'],
 [28,'Included cached egress',250,'GB / month','Separate Supabase Pro allowance.'],
 [29,'Extra cached egress',.03,'USD / GB','Supabase Pro overage.'],
 [30,'Resend Pro',20,'USD / month','Includes 50,000 emails; additional usage not assumed.'],
 [31,'Apple developer membership',99,'USD / year','Annual reserve; actual local invoice may differ.'],
 [32,'Other local running costs',0,'ZAR / month','Enter marketing, accounting, bank fees and other expenses. Zero means not included.'],
 [33,'R2 request overages',0,'USD / month','Class A/B request costs above free tiers; replace with actual usage.'],
 [34,'Other platform usage',0,'USD / month','Extra compute, database, email, MAU and other hosting usage, if needed.'],
 [35,'Primary income-tax rebate',17820,'ZAR / year','SARS 2027 tax year; under age 65.'],
 [36,'Months per year',12,'months','Annualized steady-state model, not a first partial tax-year return.'],
 [37,'Current app AI safety ceiling',2,'USD / day','Existing guard is unchanged; conservative reservations can pause usage sooner.'],
 [38,'Budget month',30,'days','Used only to compare AI forecast with the current daily guard.'],
];
for(const [r,label,x,unit,basis] of inputs){a.getRange(`B${r}:E${r}`).values=[[label,x,unit,basis]];}
a.getRange('C5:C38').setNumberFormat(num);
for(const r of [6,7,8,10,14])a.getRange(`C${r}`).setNumberFormat('0%');
for(const r of [19,23,25,27,29])a.getRange(`C${r}`).setNumberFormat('0.0000');
a.getRange('B5:E38').format.wrapText=true;
a.getRange('B5:E38').format.rowHeight=42;
a.getRange('C5:C38').format.fill='#FFF7DB';
a.getRange('C5:C38').format.font.color='#145BB7';
head(a,'B41:H41',['Contribution','Storage GiB','Price incl VAT','Billing months','AI answers / mo','Voice minutes / mo','Paying members']);
a.getRange('B42:H45').values=[['Family monthly',5,119.99,1,500,120,1000],['Family annual',5,1199.99,12,500,120,0],['Legacy monthly',25,199.99,1,1500,400,0],['Legacy annual',25,1799.99,12,1500,400,0]];
a.getRange('D42:D45').setNumberFormat(money);
a.getRange('C42:H45').format.font.color='#145BB7';
a.getRange('C42:H45').format.fill='#FFF7DB';
head(a,'B47:D47',['Annual taxable profit: lower bound','Upper bound','Rate']);
const bands=[[0,245100,.18],[245100,383100,.26],[383100,530200,.31],[530200,695800,.36],[695800,887000,.39],[887000,1878600,.41],[1878600,null,.45]];
a.getRange('B48:D54').values=bands;
a.getRange('B48:C54').setNumberFormat(money);a.getRange('D48:D54').setNumberFormat('0%');
const notes=[
 'Prices: checked in App Store Connect on 6 November 2026. Current new-subscriber South African pricing. Backend new-contribution grants are 5 GiB and 25 GiB; renewals maintain capacity, not add more each month.',
 'Storage units: Heiro grants binary GiB (1 GiB = 1,073,741,824 bytes). This budget converts those bytes to decimal GB for conservative cost planning; reconcile with vendor billing units and invoices.',
 'Consumer VAT is removed before Apple commission. Do not deduct it again from Apple proceeds. Supplier-tax reserve is separate and may overstate actual tax. No input VAT credit assumed because owner is not VAT-registered.',
 'Personal income only, under 65, no other income, deductions or credits. Tax bands apply 1 March 2026–28 February 2027. Future-year rates are not predicted; annual subscriptions are spread across 12 months for profitability, not cash-flow timing.',
 'Scale forecast only: the current R2 9 GB retained-copy limit and app US$2/day AI ceiling remain unchanged. Forecasts above those controls require a future budget decision. Free-family AI reserve does not fund full use of every free allowance.',
 'Not included unless entered above: advertising, owner remuneration, accounting, banking/FX fees, additional compute/database/API/email requests, non-modelled taxes and legal costs. No guarantee of actual net income.',
 'Supplier storage is average use over time. Model assumes one full current backup, not unlimited retained versions. Exceeding the existing Supabase spend cap can restrict service instead of silently provisioning this scale.',
 'App Store product descriptions still mention 10/50 GB and one sponsor; this differs from current backend bucket grants. This workbook does not edit Apple metadata or draft submissions.',
];
for(let i=0;i<notes.length;i++)note(a,`B${57+i}:H${57+i}`,notes[i]);
const sources=[['SARS individual tax','https://www.sars.gov.za/tax-rates/income-tax/rates-of-tax-for-individuals/'],['SARS VAT','https://www.sars.gov.za/types-of-tax/value-added-tax/'],['SARS 2026 VAT threshold','https://www.sars.gov.za/about/sars-tax-and-customs-system/budget/budget-2026-frequently-asked-questions/'],['Apple subscription proceeds','https://developer.apple.com/app-store/subscriptions/'],['Apple Small Business','https://developer.apple.com/app-store/small-business-program/'],['Apple developer membership','https://developer.apple.com/programs/enroll/'],['Supabase pricing','https://supabase.com/pricing'],['R2 pricing','https://developers.cloudflare.com/r2/pricing/'],['Resend pricing','https://resend.com/pricing'],['OpenAI pricing','https://developers.openai.com/api/docs/pricing'],['Current Apple product group','https://appstoreconnect.apple.com/apps/6802720270/distribution/subscription-groups/22339684']];
head(a,'B67:E67',['Sources checked 6 November 2026','','','URL']);
sources.forEach(([label,url],i)=>{val(a,`B${68+i}`,label);a.getRange(`C${68+i}:H${68+i}`).merge();val(a,`C${68+i}`,url);a.getRange(`C${68+i}:H${68+i}`).format.wrapText=true;});

title(m,'B2','HEIRO / BREAK-EVEN & TAKE-HOME ESTIMATE');
note(m,'B3:I3','Monthly, annualized planning model in rand. Edit blue cells on Assumptions. Default: 10,000 GB of free-family originals, one backup, 1,000 Family monthly payers and 30% Apple commission.');
head(m,'B5:C5',['Monthly waterfall','ZAR']);
const waterfall=['Customer payments, including VAT','Consumer VAT collected by Apple','Apple commission','Proceeds after VAT and Apple','Estimated operating costs','Profit before personal income tax','Estimated personal income tax','Estimated profit after income tax'];
waterfall.forEach((x,i)=>val(m,`B${i+6}`,x));
f(m,'C6','=SUM(D18:D21)');f(m,'C7','=C6-SUM(E18:E21)');f(m,'C8','=SUM(F18:F21)');f(m,'C9','=SUM(G18:G21)');f(m,'C10','=C40');f(m,'C11','=C9-C10');f(m,'C12',`=MAX(0,SUM(H29:H35)-${A(35)})/${A(36)}`);f(m,'C13','=C11-C12');
m.getRange('C6:C13').setNumberFormat(money);
m.getRange('B13:C13').format={fill:'#DAEFE8',font:{name:'Arial',bold:true,size:12,color:'#174C3B'},rowHeight:30};
note(m,'E6:I7','Apple 30% is the conservative default because Small Business approval has not been confirmed. Change to 15% if approved.');
note(m,'E9:I10','Profit is after the modelled expenses, not a guaranteed payout. Annual plans are divided by 12; cash arrives differently.');
note(m,'E12:I13','Personal income tax is charged on annual taxable profit, not total customer payments. A loss produces no tax benefit here.');
head(m,'B17:I17',['Plan','Paying members','Customer pays / mo','Ex-VAT sales','Apple fee','Proceeds','Paid storage GB','Paid AI USD']);
for(let j=0;j<4;j++){
 const r=18+j,s=42+j,u=45+j;
 f(m,`B${r}`,`=Assumptions!B${s}`);f(m,`C${r}`,`=Assumptions!H${s}`);
 f(m,`D${r}`,`=C${r}*Assumptions!D${s}/Assumptions!E${s}`);
 f(m,`E${r}`,`=D${r}/(1+${A(6)})`);f(m,`F${r}`,`=E${r}*${A(7)}`);f(m,`G${r}`,`=E${r}-F${r}`);
 f(m,`H${r}`,`=C${r}*Assumptions!C${s}*1073741824/1000000000*${A(10)}`);
 f(m,`I${r}`,`=C${r}*(Assumptions!F${s}*(${A(15)}*${A(17)}+${A(16)}*${A(18)})/1000000+Assumptions!G${s}*${A(19)})*${A(14)}`);
 f(m,`B${u}`,`=B${r}`);f(m,`C${u}`,`=Assumptions!D${s}/Assumptions!E${s}/(1+${A(6)})*(1-${A(7)})`);
 f(m,`D${u}`,`=(Assumptions!C${s}*1073741824/1000000000*${A(10)}*(${A(23)}+${A(11)}*${A(25)}+${A(12)}*${A(27)}+${A(13)}*${A(29)})+(Assumptions!F${s}*(${A(15)}*${A(17)}+${A(16)}*${A(18)})/1000000+Assumptions!G${s}*${A(19)})*${A(14)})*${A(5)}*(1+${A(8)})`);
 f(m,`E${u}`,`=C${u}-D${u}`);f(m,`F${u}`,`=IF(E${u}<=0,"Not viable",ROUNDUP($C$52/E${u},0))`);
}
m.getRange('D18:G21').setNumberFormat(money);m.getRange('H18:H21').setNumberFormat(num);m.getRange('I18:I21').setNumberFormat(usd);
head(m,'B25:C25',['Monthly operating-cost build','Value']);
const costlabels=['Original storage, free + paid (GB)','Supabase storage overage (USD)','R2 backup storage (USD)','Supabase uncached downloads (USD)','Supabase cached downloads (USD)','Paid-family AI use (USD)','Additional AI reserve (USD)','Supabase Pro (USD)','Resend Pro (USD)','Apple membership monthly (USD)','Other platform / request costs (USD)','Total operating costs (USD)','Converted, including tax reserve (ZAR)','Other local expenses (ZAR)','Total operating costs (ZAR)'];
costlabels.forEach((x,i)=>val(m,`B${26+i}`,x));
const costformulas=[
 `=${A(9)}+SUM(H18:H21)`, `=MAX(0,C26-${A(22)})*${A(23)}`,`=MAX(0,ROUNDUP(C26*${A(11)},0)-${A(24)})*${A(25)}`,
 `=MAX(0,C26*${A(12)}-${A(26)})*${A(27)}`,`=MAX(0,C26*${A(13)}-${A(28)})*${A(29)}`,
 '=SUM(I18:I21)',`=${A(20)}`,`=${A(21)}`,`=${A(30)}`,`=${A(31)}/${A(36)}`,`=${A(33)}+${A(34)}`,
 '=SUM(C27:C36)',`=C37*${A(5)}*(1+${A(8)})`,`=${A(32)}`,'=SUM(C38:C39)'];
costformulas.forEach((x,i)=>f(m,`C${26+i}`,x));m.getRange('C26').setNumberFormat(num);m.getRange('C27:C37').setNumberFormat(usd);m.getRange('C38:C40').setNumberFormat(money);
val(m,'E26','Annual taxable profit');f(m,'F26',`=MAX(0,C11*${A(36)})`);m.getRange('F26').setNumberFormat(money);
head(m,'E28:H28',['Tax band','Taxable portion','Rate','Annual tax']);
for(let j=0;j<7;j++){const r=29+j,s=48+j;val(m,`E${r}`,`Band ${j+1}`);f(m,`F${r}`,j===6?`=MAX(0,$F$26-Assumptions!B${s})`:`=MAX(0,MIN($F$26,Assumptions!C${s})-Assumptions!B${s})`);f(m,`G${r}`,`=Assumptions!D${s}`);f(m,`H${r}`,`=F${r}*G${r}`);}
m.getRange('F29:F35').setNumberFormat(money);m.getRange('G29:G35').setNumberFormat('0%');m.getRange('H29:H35').setNumberFormat(money);
note(m,'E37:I40','Tax: SARS 2027 year, under 65, Heiro is the only income. Annual rebate is deducted before dividing by 12. Future tax rates, other deductions, medical credits and any loss offsets are excluded.');
head(m,'B44:F44',['All payers on this plan','Proceeds / payer','Extra cost / payer','Contribution / payer','Break-even payers']);
m.getRange('C45:E48').setNumberFormat(money);m.getRange('F45:F48').setNumberFormat('#,##0');
val(m,'B51','Base costs before paid members (USD)');
f(m,'C51',`=${A(21)}+${A(30)}+${A(31)}/${A(36)}+${A(20)}+${A(33)}+${A(34)}+MAX(0,${A(9)}-${A(22)})*${A(23)}+MAX(0,ROUNDUP(${A(9)}*${A(11)},0)-${A(24)})*${A(25)}+MAX(0,${A(9)}*${A(12)}-${A(26)})*${A(27)}+MAX(0,${A(9)}*${A(13)}-${A(28)})*${A(29)}`);
val(m,'B52','Base costs before paid members (ZAR)');f(m,'C52',`=C51*${A(5)}*(1+${A(8)})+${A(32)}`);m.getRange('C51').setNumberFormat(usd);m.getRange('C52').setNumberFormat(money);
val(m,'E51','AI forecast / month');f(m,'F51','=C31+C32');val(m,'E52','Current AI safety allowance');f(m,'F52',`=${A(37)}*${A(38)}`);val(m,'E53','Future AI budget above guard');f(m,'F53','=MAX(0,F51-F52)');m.getRange('F51:F53').setNumberFormat(usd);
note(m,'B55:I56','Break-even counts paying contributors, not families: several people can pay in one family. Calculation conservatively charges each added payer at full marginal rates, without unused free vendor allowances. Non-positive contribution is not sustainable at the selected usage. At break-even personal income tax is zero.');
note(m,'B58:I59','This is an economic forecast, not permission to raise limits. Current AI and backup protections stay in place. If forecast AI exceeds the guard, requests would pause; supporting that projected usage needs a future budget change.');
note(m,'B61:I62','Check the Assumptions sheet for sources, exclusions and the mismatch in Apple storage descriptions. Default example uses full paid storage and paid AI usage, plus only a US$60 reserve for all other AI activity.');
for(const r of [9,11,40,52])m.getRange(`B${r}:C${r}`).format.borders={top:{style:'thin',color:'#A8C1C5'}};
m.getRange('B5:B62').format.wrapText=true;
m.getRange('E51:E53').format.wrapText=true;m.getRange('E51:F53').format.rowHeight=36;
await wb.recalculate();
const result = m.getRange('B6:C13').values;
console.log(JSON.stringify({summary:result,breakEven:m.getRange('B45:F48').values}));
// Independently verify the default and sensitivity calculations before export.
function independent(n,comm=.30,traffic=.1){
 const gb=10000+n*5*2**30/1e9;
 const usdCost=25+20+99/12+60+n*.738+Math.max(0,gb-100)*.0213+Math.max(0,Math.ceil(gb)-10)*.015+Math.max(0,gb*traffic-250)*.09;
 const gross=n*119.99, ex=gross/1.15, proceeds=ex*(1-comm),cost=usdCost*18*1.15,profit=proceeds-cost;
 const annual=Math.max(profit*12,0);let tax=0;
 for(const [lo,hi,rate] of bands)tax+=Math.max(0,Math.min(annual,hi??annual)-lo)*rate;
 tax=Math.max(0,tax-17820)/12;
 return [gross,gross-ex,ex*comm,proceeds,cost,profit,tax,profit-tax];
}
function check(expected){const actual=m.getRange('C6:C13').values.flat();actual.forEach((x,i)=>{if(typeof x!=='number'||Math.abs(x-expected[i])>.001)throw new Error(`Value mismatch ${i}: ${x} vs ${expected[i]}`);});}
check(independent(1000));
val(a,'H42',0);await wb.recalculate();check(independent(0));
val(a,'H42',500);val(a,'C7',.15);await wb.recalculate();check(independent(500,.15));
val(a,'C12',1);await wb.recalculate();check(independent(500,.15,1));
val(a,'H42',1000);val(a,'C7',.30);val(a,'C12',.1);await wb.recalculate();check(independent(1000));
for(const s of [m,a])for(const row of s.getRange('B1:I80').values)for(const x of row){if(typeof x==='string'&&/^#(REF!|DIV\/0!|VALUE!|NAME\?|NUM!|N\/A|SPILL!|CALC!)/.test(x))throw new Error(x);}
const previews=[['Model','B2:I22','model-summary.png'],['Model','B25:I62','model-costs.png'],['Assumptions','B41:H64','model-assumptions.png']];
for(const [sheetName,range,name]of previews){const img=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(out+name,new Uint8Array(await img.arrayBuffer()));}
const file=await SpreadsheetFile.exportXlsx(wb);await file.save(out+'Heiro_break_even.xlsx');
await fs.writeFile(out+'verified-results.json',JSON.stringify({default:independent(1000),scenarios:[100,500,1000].map(n=>({n,apple30:independent(n),apple15:independent(n,.15)})),breakEven:m.getRange('B45:F48').values},null,2));
console.log('Workbook exported and numeric scenario checks passed.');
