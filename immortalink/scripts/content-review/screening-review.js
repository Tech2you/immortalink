// Separate queue and decisions: automatic holds must never invoke report Restore.
function initScreeningReview({api,status,element,onSelect}) {
  const $=selector=>document.querySelector(selector);
  let generation=0,queueGeneration=0,ended=false;
  const blobs=[];
  const reasons={HUMAN_REVIEW_REQUIRED:'Flagged for human review',RETRY_LIMIT:'Automatic check could not finish'};
  const states={open:'Awaiting review',reviewing:'Under review',held:'Kept private',approved:'Approved',obsolete:'Closed or changed'};
  function clear(){generation++;for(const url of blobs)URL.revokeObjectURL(url);blobs.length=0;}
  async function refresh(){
    const request=++queueGeneration;
    const rows=await api('/api/screening/queue',{state:$('#screening-filter').value});
    if(ended || request!==queueGeneration)return;
    $('#screening-queue').replaceChildren();
    if(!rows.length)$('#screening-queue').append(element('li','No checks in this view.'));
    for(const row of rows){
      const li=element('li',''),button=element('button',`${reasons[row.reason]||'Automatic check'}\n${states[row.status]||'Unknown status'}\n${new Date(row.created_at).toLocaleString()}`);
      button.onclick=()=>open(row.id).catch(e=>status(e.message));li.append(button);$('#screening-queue').append(li);
    }
    try {
      const health=await api('/api/screening/health');
      if(ended || request!==queueGeneration)return;
      if(!health || ['enabled','email_enabled','push_enabled'].some(k=>typeof health[k]!=='boolean') ||
        ['attention','omitted','pending','accepted','email_attempts','push_attempts','email_daily_limit','push_daily_limit'].some(k=>!Number.isSafeInteger(health[k]) || health[k]<0))throw Error('Unavailable');
      const limited=health.email_attempts>=health.email_daily_limit || health.push_attempts>=health.push_daily_limit;
      const warning=!health.enabled || !health.email_enabled || !health.push_enabled ? 'Automatic-check delivery is paused. Review this queue directly.' :
        health.attention || health.omitted || limited ? 'Automatic-check delivery needs attention. Review this queue directly.' : 'Automatic-check delivery checked.';
      $('#screening-health').textContent=`${warning} Pending: ${health.pending}. Accepted by provider: ${health.accepted}. Needs attention: ${health.attention}. Omitted: ${health.omitted}.`;
    } catch {
      if(!ended && request===queueGeneration)$('#screening-health').textContent='Automatic-check delivery status unavailable. Review this queue directly.';
    }
  }
  async function open(id){
    if(ended)return;
    clear();onSelect();const request=generation;
    $('#case').replaceChildren(element('h2','Opening automatic check...'));
    const data=await api('/api/screening/case',{id});if(ended || request!==generation)return;
    const fragment=$('#screening-case-template').content.cloneNode(true);
    fragment.querySelector('.state').textContent=states[data.report.status]||'Unknown status';
    fragment.querySelector('.reference').textContent=data.report.id;
    const details=fragment.querySelector('.details');
    for(const [name,value] of [['Reason',reasons[data.report.reason]||'Automatic check'],['Received',new Date(data.report.createdAt).toLocaleString()]])details.append(element('dt',name),element('dd',value));
    fragment.querySelector('.scope').textContent=data.scopeNote;
    const content=fragment.querySelector('.content');
    if(!data.available)content.append(element('p','This version is unavailable or restricted. No replacement memory has been opened.'));
    for(const [name,value] of Object.entries(data.fields))content.append(element('h3',name),element('p',value));
    const form=fragment.querySelector('.decision'),button=form.querySelector('button');
    const actionable=['open','reviewing','held'].includes(data.report.status),opened=new Set();
    const approve=form.querySelector('[value="approve"]');
    const updateApproval=()=>{approve.disabled=!actionable || !data.available || opened.size!==data.media.length;};
    updateApproval();form.querySelector('[value="obsolete"]').disabled=data.available;
    for(const field of form.elements)field.disabled=!actionable || field.disabled;
    for(const [index,media] of data.media.entries()){
      const wrapper=element('div','');wrapper.className='attachment';
      const preview=element('button',`Show image ${index+1}`);wrapper.append(preview);
      preview.onclick=async()=>{
        preview.disabled=true;
        try{
          const blob=await api('/api/screening/media',{id,mediaId:media.id,revision:data.revision});
          if(ended || request!==generation)return;
          const url=URL.createObjectURL(blob);blobs.push(url);
          const img=document.createElement('img');img.alt=`Held attachment ${index+1}`;
          img.onload=()=>{if(!ended && request===generation){opened.add(media.id);updateApproval();preview.textContent='Preview opened';}};
          img.onerror=()=>{status('Image could not display. Reopen the check before approving.');};
          img.src=url;wrapper.append(img);
        }catch(error){if(!ended && request===generation){status(error.message);preview.disabled=false;}}
      };
      fragment.querySelector('.attachments').append(wrapper);
    }
    form.onsubmit=async event=>{
      event.preventDefault();button.disabled=true;const values=new FormData(form);
      try{
        if(values.get('confirm')!==id)throw new Error('Enter this exact check reference to confirm.');
        const action=values.get('action');
        if(action==='approve' && (approve.disabled || !confirm('Approve only this reviewed version for family sharing?')))return;
        const result=await api('/api/screening/action',{id,revision:data.revision,action,notes:values.get('notes'),confirm:id});
        if(ended || request!==generation)return;
        await open(id);await refresh();status(`Check decision recorded: ${states[result.status]||result.status}.`);
      }catch(error){if(!ended && request===generation)status(error.message);}
      finally{button.disabled=!actionable;}
    };
    $('#case').replaceChildren(fragment);status('Automatic check opened. Preview access is recorded.');
  }
  $('#screening-panel').hidden=false;
  $('#screening-refresh').onclick=()=>refresh().catch(e=>status(e.message));
  $('#screening-filter').onchange=()=>refresh().catch(e=>status(e.message));
  $('#screening-lookup').onsubmit=event=>{event.preventDefault();open($('#screening-reference').value.trim()).catch(e=>status(e.message));};
  return {refresh,clear,end(){ended=true;queueGeneration++;clear();$('#screening-panel').hidden=true;$('#screening-queue').replaceChildren();}};
}
