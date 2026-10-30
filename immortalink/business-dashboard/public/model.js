export const PRODUCTS = new Set(['everroots.family.monthly','everroots.family.annual','everroots.legacy.monthly','everroots.legacy.annual']);
export function financialSummary(entries, report) {
  const sum = kind => entries.filter(e => e.kind === kind).reduce((s,e) => s + Number(e.amount)*Number(e.zar_rate),0);
  const has = kind => entries.some(e => e.kind === kind);
  const proceeds = has('apple_proceeds') ? sum('apple_proceeds') : null;
  const costs = has('expense') || report?.costs_complete ? sum('expense') : null;
  return {proceeds,costs,bank:has('bank_payment')?sum('bank_payment'):null,
    contribution: proceeds!==null && costs!==null && report?.costs_complete ? proceeds-costs : null,
    churn: report?.starting_payers>0 && report.lost_starting_payers!=null ? 100*report.lost_starting_payers/report.starting_payers : null,
    mrr:report?.mrr_zar==null?null:Number(report.mrr_zar)};
}
// Quoted CSV and Apple TSV, including embedded newlines. Never evaluate spreadsheet formulas.
export function parseDelimited(text) {
  if (text.length>5*1024*1024) throw Error('Use a report smaller than 5 MB.');
  text=text.replace(/^\uFEFF/,'');
  const delimiter=text.split(/\r?\n/,1)[0].includes('\t')?'\t':',';
  const rows=[];let row=[],field='',quoted=false;
  for(let i=0;i<text.length;i++) {
    const c=text[i];
    if(c==='"') {if(quoted&&text[i+1]==='"'){field+='"';i++;}else if(quoted||field===''){quoted=!quoted;}else throw Error('Invalid quotation in the report.');}
    else if(!quoted&&(c===delimiter||c==='\n'||c==='\r')) {
      row.push(field);field='';
      if(c!==delimiter){if(row.some(x=>x.trim()))rows.push(row);row=[];if(c==='\r'&&text[i+1]==='\n')i++;}
    } else field+=c;
    if(rows.length>50000)throw Error('Use a report with fewer than 50,000 rows.');
  }
  if(quoted)throw Error('The report contains an unfinished quoted field.');
  row.push(field);if(row.some(x=>x.trim()))rows.push(row);
  if(rows.length<2)throw Error('No report rows found.');
  return rows;
}
function reportDate(value) {
  const m=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value.trim());
  if(!m)throw Error('Apple report dates must use MM/DD/YYYY.');
  const iso=`${m[3]}-${m[1]}-${m[2]}`;
  if(Number.isNaN(Date.parse(iso))||new Date(iso).toISOString().slice(0,10)!==iso)throw Error('Invalid report date.');
  return iso;
}
export function parseAppleReport(text) {
  const [headers,...rows]=parseDelimited(text);
  const index=name=>headers.findIndex(h=>h.trim().toLowerCase()===name.toLowerCase());
  const fields=['Start Date','End Date','Vendor Identifier','Extended Partner Share','Partner Share Currency'];
  const indexes=fields.map(index);
  if(indexes.some(i=>i<0))throw Error('Choose an Apple financial report with Extended Partner Share. Sales summaries use a different format.');
  const [start,end,sku,amount,currency]=indexes,groups=new Map(),canonical=[];let matched=0,ignored=0;
  for(const row of rows) {
    if(!PRODUCTS.has(row[sku]?.trim())){ignored++;continue;}
    if(row.length!==headers.length)throw Error('A Heiro report row has missing columns.');
    const from=reportDate(row[start]),to=reportDate(row[end]),code=row[currency].trim(),value=row[amount].trim();
    if(to<from||Date.parse(to)-Date.parse(from)>40*86400000)throw Error('Check the financial reporting period.');
    if(!/^[A-Z]{3}$/.test(code)||!/^[-+]?\d+(\.\d{1,8})?$/.test(value)||Math.abs(Number(value))>1e9)throw Error('Invalid currency or amount in the report.');
    const key=`${from}|${to}|${code}`;
    const g=groups.get(key)||{period_start:from,period_end:to,currency:code,amount:0,rows:0};
    g.amount+=Number(value);g.rows++;groups.set(key,g);matched++;
    canonical.push(JSON.stringify(row.map(x=>x.trim())));
  }
  if(!matched)throw Error('No recognised Heiro subscription products in this report.');
  const periods=new Set([...groups.values()].map(g=>`${g.period_start}|${g.period_end}`));
  if(periods.size!==1)throw Error('Import one Apple fiscal period at a time.');
  const result=[...groups.values()].map(g=>({...g,amount:Math.round((g.amount+Number.EPSILON)*100)/100}));
  return {groups:result,matched,ignored,canonical:JSON.stringify({headers:headers.map(x=>x.trim()),rows:canonical.sort()})};
}
export async function digest(text) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
