let csrf; let current; let generation=0; let sessionGeneration=0; const blobs=[];
const $=(selector)=>document.querySelector(selector);
const status=(text)=> { $('#status').textContent=text; };
function clearMedia(){ for(const url of blobs) URL.revokeObjectURL(url); blobs.length=0; }
async function api(path,body={}) {
  const requestSession=sessionGeneration;
  const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json',...(csrf?{'X-Review-CSRF':csrf}:{})},body:JSON.stringify(body)});
  if(path!=='/api/logout' && requestSession!==sessionGeneration)throw new Error('Session ended.');
  if(!response.ok){ const error=await response.json(); throw new Error(error.error || 'Review request failed.'); }
  return path==='/api/media'?response.blob():response.json();
}
function element(tag,text){ const node=document.createElement(tag); node.textContent=text; return node; }
async function queue(){
  const reports=await api('/api/queue'); $('#queue').replaceChildren();
  if(!reports.length) $('#queue').append(element('li','No open reports.'));
  for(const report of reports){
    const li=element('li',''); const button=element('button',`${report.reason.replaceAll('_',' ')}\n${report.target_kind.replaceAll('_',' ')} · ${report.status}\n${new Date(report.created_at).toLocaleString()}`);
    button.onclick=()=>openCase(report.id).catch((e)=>status(e.message)); li.append(button); $('#queue').append(li);
  }
}
async function openCase(id){
  const request=++generation; current=null; clearMedia(); $('#case').replaceChildren(element('h2','Opening case...'));
  const data=await api('/api/case',{id}); if(request!==generation)return; current=data;
  const fragment=$('#case-template').content.cloneNode(true);
  fragment.querySelector('h2').textContent=data.report.kind.replaceAll('_',' ');
  fragment.querySelector('.state').textContent=data.report.status;
  fragment.querySelector('.reference').textContent=data.report.id;
  const details=fragment.querySelector('.details');
  for(const [key,value] of [['Reason',data.report.reason.replaceAll('_',' ')],['Received',new Date(data.report.createdAt).toLocaleString()]]) details.append(element('dt',key),element('dd',value));
  fragment.querySelector('.statement').textContent=data.report.details || 'No statement supplied.';
  fragment.querySelector('.scope').textContent=data.scopeNote;
  const content=fragment.querySelector('.content');
  if(!data.available) content.append(element('p','Target is deleted, moved or unavailable. No other archive content has been opened.'));
  for(const [name,value] of Object.entries(data.fields)){ content.append(element('h3',name),element('p',value)); }
  for(const [index,media] of data.media.entries()){
    const wrapper=element('div',''); wrapper.className='attachment';
    const button=element('button',`${media.kind==='audio'?'Open audio':'Show image'} ${index+1}`); wrapper.append(button);
    button.onclick=async()=>{
      button.disabled=true;
      try{
        const blob=await api('/api/media',{id,mediaId:media.id,revision:data.revision});
        if(request!==generation)return;
        const url=URL.createObjectURL(blob); blobs.push(url);
        const player=document.createElement(media.kind==='audio'?'audio':'img'); player.src=url;
        if(media.kind==='audio'){player.controls=true;player.preload='none';}else player.alt=`Reported attachment ${index+1}`;
        wrapper.append(player); button.textContent='Preview opened';
      }catch(error){status(error.message);button.disabled=false;}
    };
    fragment.querySelector('.attachments').append(wrapper);
  }
  for(const action of ['suspend','reinstate']) fragment.querySelector(`[value="${action}"]`).disabled=!data.report.accountActionAvailable;
  fragment.querySelector('.decision').onsubmit=async(event)=>{
    event.preventDefault(); const form=event.target; const values=new FormData(form); const button=form.querySelector('button'); button.disabled=true;
    try{
      if(values.get('confirm')!==id)throw new Error('Enter this exact report reference to confirm.');
      const action=values.get('action');
      if(['suspend','reinstate'].includes(action) && !confirm('Apply this action to the identified contributor account, not just this item?'))return;
      const result=await api('/api/action',{id,revision:data.revision,action,notes:values.get('notes'),confirm:values.get('confirm')});
      status(`Decision recorded: ${result.action}.`); await openCase(id); await queue();
    }catch(error){status(error.message);}finally{button.disabled=false;}
  };
  $('#case').replaceChildren(fragment); status('Case opened. Preview access is recorded.');
}
$('#refresh').onclick=()=>queue().catch((e)=>status(e.message));
$('#lookup').onsubmit=(event)=>{event.preventDefault();openCase($('#reference').value.trim()).catch((e)=>status(e.message));};
function clearSession(){sessionGeneration++;generation++;current=null;csrf=null;clearMedia();$('#case').replaceChildren();$('#queue').replaceChildren();status('Session ended. Close this tab.');}
$('#logout').onclick=async()=>{const closing=api('/api/logout');clearSession();try{await closing;}catch{status('Local session cleared. Close this tab and stop the console.');}};
window.addEventListener('pagehide',clearMedia);
(async()=>{
  const key=location.hash.slice(1); history.replaceState(null,'',location.pathname);
  const session=await api('/session',key?{key}:{});csrf=session.csrf;$('#reviewer').textContent=session.reviewer;
  setTimeout(clearSession,session.expiresInMs);
  await queue();status('Private review session ready.');
  const health=await api('/api/health');$('#health').textContent=health.needs_attention?'Alert delivery needs attention. Check the queue directly.':'Alert health checked.';
})().catch((e)=>status(e.message));
