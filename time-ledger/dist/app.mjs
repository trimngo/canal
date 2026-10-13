import {GOOGLE_CLIENT_ID} from './config.mjs';
import {DEFAULT_CATEGORIES,UNCLASSIFIED,CONFLICT,dateParts,periodBounds,normalizeEvent,allocate,displayDuration,makeEventDraft} from './core.mjs';
import {READ_SCOPES,WRITE_SCOPE,CalendarError,listCalendars,listEvents,createEvent,calendarRequest,eventPath} from './google.mjs';

const $=id=>document.getElementById(id),escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const safeGoogleLink=url=>{try{const u=new URL(url);return u.protocol==='https:'&&['calendar.google.com','www.google.com'].includes(u.hostname)?u.href:null;}catch{return null;}};
let categories=structuredClone(DEFAULT_CATEGORIES),assignments={},series={},selected=[],calendars=[],events=[],tz='Europe/Berlin',period='today',filter=null,scheduled=false;
let token=null,expires=0,writeGranted=false,account=null,connected=false,busy=false,syncVersion=0,lastSync=null,syncErrors=[],storageFailed=false;
let editedCategory=null,editedEvent=null,pendingSave=null,saving=false,toastTimer,selectedWriteCalendar=null;
function toast(message){$('toast').textContent=message;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),5500);}
function prefsKey(){return 'time-ledger:v1:'+account;}
function persist(){if(!account)return;try{localStorage.setItem(prefsKey(),JSON.stringify({categories,assignments,series,selected,tz,selectedWriteCalendar}));}catch{storageFailed=true;toast('Preferences could not be saved. They will last only until you close this page.');}}
function loadPrefs(){
  categories=structuredClone(DEFAULT_CATEGORIES);assignments={};series={};selected=[];tz=calendars.find(c=>c.primary)?.timeZone||Intl.DateTimeFormat().resolvedOptions().timeZone||'Europe/Berlin';selectedWriteCalendar=null;
  try{const p=JSON.parse(localStorage.getItem(prefsKey())||'null');if(p){
    if(Array.isArray(p.categories)&&p.categories.every(c=>typeof c.id==='string'&&typeof c.name==='string'&&Array.isArray(c.keywords)))categories=p.categories.map(c=>({...c,color:/^#[0-9a-f]{6}$/i.test(c.color)?c.color:'#2f60ed',keywords:c.keywords.filter(k=>typeof k==='string')}));
    assignments=p.assignments&&typeof p.assignments==='object'?p.assignments:{};series=p.series&&typeof p.series==='object'?p.series:{};selected=Array.isArray(p.selected)?p.selected.filter(id=>calendars.some(c=>c.id===id)):[];
    if(p.tz){new Intl.DateTimeFormat('en',{timeZone:p.tz});tz=p.tz;}selectedWriteCalendar=p.selectedWriteCalendar;
  }else selected=[(calendars.find(c=>c.primary)||calendars[0])?.id].filter(Boolean);}catch{selected=[(calendars.find(c=>c.primary)||calendars[0])?.id].filter(Boolean);}
}
function validSession(){return connected&&token&&Date.now()<expires;}
function invalidate(message){token=null;expires=0;writeGranted=false;connected=false;syncVersion++;events=[];lastSync=null;syncErrors=[];calendars=[];pendingSave=null;render();renderSettings();if(message)toast(message);}
function disconnect(){const old=token;invalidate('Disconnected. Loaded Calendar data has been cleared.');account=null;categories=structuredClone(DEFAULT_CATEGORIES);selected=[];assignments={};series={};render();renderSettings();if(old&&window.google?.accounts?.oauth2)google.accounts.oauth2.revoke(old,()=>{});}
function googleReady(){return Boolean(window.google?.accounts?.oauth2);}
function authorize(scopes){
  return new Promise((resolve,reject)=>{
    if(!googleReady()){reject(new Error('Google’s sign-in service is still loading or was blocked. Wait a moment and try again in Safari.'));return;}
    const client=google.accounts.oauth2.initTokenClient({client_id:GOOGLE_CLIENT_ID,scope:scopes,include_granted_scopes:true,...(account?.includes('@')?{hint:account}:{}),callback:response=>{
      if(response.error){reject(new Error(response.error_description||'Google authorization was not completed.'));return;}
      if(!google.accounts.oauth2.hasGrantedAllScopes(response,...READ_SCOPES.split(' '))){reject(new Error('Read access was not granted. Select Calendar permissions in Google’s consent screen.'));return;}
      if(scopes.includes(WRITE_SCOPE)&&!google.accounts.oauth2.hasGrantedAllScopes(response,WRITE_SCOPE)){reject(new Error('Event-write permission was not granted. Your Calendar was not changed.'));return;}
      token=response.access_token;expires=Date.now()+Number(response.expires_in||3600)*1000-30000;
      writeGranted=google.accounts.oauth2.hasGrantedAllScopes(response,WRITE_SCOPE);resolve(response);
    },error_callback:err=>reject(new Error(err.type==='popup_closed'?'Google’s authorization window was closed.': 'Google’s authorization window could not open. Try connecting in Safari.'))});
    client.requestAccessToken({prompt:account?'':'select_account'});
  });
}
async function connect(){
  if(busy||saving)return;busy=true;renderSettings();render();
  try{await authorize(READ_SCOPES);const list=await listCalendars(token);const next=(list.find(c=>c.primary)||list[0])?.id;if(!next)throw new Error('No calendars are available for this Google account.');
    events=[];lastSync=null;syncErrors=[];calendars=list;account=next;connected=true;loadPrefs();renderSettings();await sync();
    toast('Connected directly to Google Calendar.');
  }catch(err){invalidate(err.message);}finally{busy=false;render();renderSettings();}
}
async function sync(){
  if(!validSession()){if(connected)invalidate('Your Google session expired. Reconnect to refresh.');return;}
  const version=++syncVersion,bounds=periodBounds(Date.now(),tz,'week'),ids=[...selected],old=[...events];
  busy=true;syncErrors=[];render();
  const results=await Promise.allSettled(ids.map(async id=>({id,rows:await listEvents(token,id,bounds.start,bounds.end)})));
  if(version!==syncVersion)return;
  if(results.some(r=>r.status==='rejected'&&r.reason.status===401)){busy=false;invalidate('Your Google session expired. Reconnect to refresh.');return;}
  let next=[],failed=[];
  results.forEach((r,i)=>{
    const calendar=calendars.find(c=>c.id===ids[i]);
    if(r.status==='fulfilled')next.push(...r.value.rows.map(raw=>normalizeEvent(raw,calendar)).filter(Boolean));
    else{failed.push({name:calendar?.summary||'Calendar',message:r.reason.message});next.push(...old.filter(e=>e.calendarId===ids[i]));}
  });
  events=next;syncErrors=failed;if(!failed.length)lastSync=Date.now();busy=false;render();renderSettings();
}
function cat(id){return categories.find(c=>c.id===id)||[UNCLASSIFIED,CONFLICT].find(c=>c.id===id)||UNCLASSIFIED;}
function fmtTime(ms){return new Intl.DateTimeFormat('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit'}).format(ms);}
function fmtDate(ms,opts={}){return new Intl.DateTimeFormat('en-GB',{timeZone:tz,day:'numeric',month:'short',...opts}).format(ms);}
function options(includeUnknown=false){return [...categories,...(includeUnknown?[UNCLASSIFIED]:[])].map(c=>`<option value="${escape(c.id)}">${escape(c.name)}</option>`).join('');}
function render(){
  if(connected&&Date.now()>=expires){invalidate('Your Google session expired. Reconnect to refresh.');return;}
  const now=Date.now(),bounds=periodBounds(now,tz,period),data=allocate(events.filter(e=>selected.includes(e.calendarId)),bounds,categories,assignments,series);
  $('source-label').textContent=connected?'Google Calendar':'Connect Calendar';document.querySelector('.status-dot').classList.toggle('imported',connected);
  $('today-button').setAttribute('aria-pressed',String(period==='today'));$('week-button').setAttribute('aria-pressed',String(period==='week'));
  $('period-caption').textContent=period==='today'?fmtDate(now,{weekday:'short'}):fmtDate(bounds.start)+' – '+fmtDate(bounds.end-1);
  $('date-caption').textContent=tz.split('/').pop().replaceAll('_',' ');
  const minutes=Math.floor(data.total/60000);
  $('total-time').innerHTML=connected?`${Math.floor(minutes/60)}h <span>${String(minutes%60).padStart(2,'0')}m</span>`:'—';
  $('summary-label').textContent=connected?'of elapsed calendar time':'Connect to see your calendar time';
  const slices=Object.entries(data.totals).filter(([,ms])=>ms>0),count=slices.length;
  $('category-count').textContent=count;
  let stop=0;const stops=slices.map(([id,ms])=>{const a=stop;stop+=ms/data.total*100;return `${cat(id).color} ${a}% ${stop}%`;});
  $('donut').style.background=stops.length?`conic-gradient(${stops.join(',')})`:'#eaeef5';
  $('allocation-strip').innerHTML=slices.map(([id,ms])=>`<span style="background:${cat(id).color};flex:${ms/data.total}"></span>`).join('');
  $('future-summary').textContent=connected?`${displayDuration(data.scheduled.total)} scheduled for the rest of ${period==='today'?'today':'this week'} · ${data.upcoming.length} event${data.upcoming.length===1?'':'s'}`:'Connect securely through Google. Your calendar stays yours.';
  const available=[...categories,UNCLASSIFIED,...(data.totals.overlap?[CONFLICT]:[])];
  $('category-list').innerHTML=available.map(c=>{const ms=data.totals[c.id]||0,pct=data.total?ms/data.total*100:0;return `<div class="category-row"><button class="category-main" data-filter="${escape(c.id)}" aria-label="View ${escape(c.name)} events"><div class="category-top"><span class="category-dot" style="background:${c.color}"></span><span class="category-name">${escape(c.name)}</span>${c.important?'<span class="important-label">★ Important</span>':''}</div><div class="category-bar"><span style="width:${pct}%;background:${c.color}"></span></div></button><div class="category-value">${connected?displayDuration(ms):'—'}<span>${connected?(pct<1&&pct>0?'<1':Math.round(pct))+'%':' '}</span></div>${categories.some(x=>x.id===c.id)?`<button class="category-add" data-add-category="${escape(c.id)}" aria-label="Add time for ${escape(c.name)}">＋</button>`:'<span style="width:32px"></span>'}</div>`;}).join('');
  $('overlap-note').textContent=data.totals.overlap?`${displayDuration(data.totals.overlap)} of conflicting overlaps counts once.`:'';
  const important=categories.filter(c=>c.important).sort((a,b)=>(data.totals[a.id]||0)-(data.totals[b.id]||0))[0];
  $('intent-title').textContent=important?`Make space for ${important.name.toLowerCase()}.`:'Make space for what matters.';
  $('intent-copy').textContent=connected&&important?`${displayDuration(data.totals[important.id]||0)} of your calendar time has gone here ${period==='today'?'today':'this week'}. A small block is a good place to start.`:'Star an important category, then give it a little calendar space.';
  $('intent-actions').innerHTML=`<button class="button" data-add-category="${escape(important?.id||categories[0]?.id||'')}">＋ Make a 30-minute block</button>`;
  let list=scheduled?data.upcoming:data.elapsed;
  if(filter==='overlap')list=list.filter(e=>data.elapsed.some(other=>other.key!==e.key&&other.category!==e.category&&Math.min(e.end,other.end,now)>Math.max(e.start,other.start,bounds.start)));
  else if(filter)list=list.filter(e=>e.category===filter);
  $('events-heading').textContent=filter?cat(filter).name:'The time behind the numbers';$('clear-filter').hidden=!filter;
  $('events-subtitle').textContent=filter?'Events in this category.':'Calendar events, one at a time.';
  $('past-events').classList.toggle('active',!scheduled);$('future-events').classList.toggle('active',scheduled);$('future-count').textContent=data.upcoming.length;
  $('event-list').innerHTML=list.length?list.map(e=>{
    const duration=scheduled?Math.max(0,Math.min(e.end,bounds.end)-Math.max(e.start,now,bounds.start)):Math.max(0,Math.min(e.end,now,bounds.end)-Math.max(e.start,bounds.start));
    return `<div class="event-row"><div class="event-time">${fmtTime(e.start)}<span>${period==='week'?fmtDate(e.start):fmtTime(e.end)}</span></div><div class="event-line" style="background:${cat(e.category).color}"></div><div class="event-body"><button class="event-title" data-event="${escape(e.key)}">${escape(e.title)}</button><div class="event-category"><button data-event="${escape(e.key)}">${escape(cat(e.category).name)} · ${escape(e.reason)}</button></div></div><span class="event-duration" title="Event duration before resolving overlap">${displayDuration(duration)}</span></div>`;
  }).join(''):`<div class="empty-state"><strong>${!connected?'Your calendar tells the story.':!selected.length?'Choose a calendar.':filter?'No events here yet.':scheduled?'Nothing scheduled next.':'No elapsed events in this period.'}</strong>${!connected?'Connect Google Calendar to see your own breakdown.':!selected.length?'Select calendars in Settings.':'Add a block for something important.'}</div>`;
  $('mode-notice').innerHTML=!connected?'<span>Connect your calendar to turn plans into a time breakdown.</span><button class="text-button" data-connect>Connect ↗</button>':syncErrors.length?`<span>Refresh incomplete. Retained events may be stale. ${escape(syncErrors.map(e=>e.name+': '+e.message).join(' '))}</span>`:`<span>${busy?'Reading Google Calendar…':'Live Google Calendar · Selected calendars only.'}</span><button class="text-button" data-settings>Manage</button>`;
  $('updated-label').textContent=lastSync?'Last read '+fmtTime(lastSync)+(storageFailed?' · Preferences not saved':''):'';
  $('refresh-button').disabled=busy||!connected;
}
function renderSettings(){
  $('connection-heading').textContent=connected?'Connected directly to Google Calendar.':'Connect directly to Google Calendar.';
  $('connection-copy').textContent=connected?'Calendar events are read directly from Google. Category preferences stay on this device.':'Authorize read access to see your time. Google will ask for event-write permission when you save your first block.';
  $('connect-button').hidden=connected;$('connect-button').disabled=busy;$('connect-button').textContent=busy?'Connecting…':'Connect Google Calendar';$('disconnect-button').hidden=!connected;
  $('calendar-list').innerHTML=calendars.length?calendars.map(c=>`<div class="calendar-setting"><label><input type="checkbox" data-calendar="${escape(c.id)}" ${selected.includes(c.id)?'checked':''}>${escape(c.summary||c.id)}${c.primary?' · Primary':''}</label></div>`).join(''):'<p class="subtle">Your calendars will appear after connecting.</p>';
  $('category-settings').innerHTML=categories.map(c=>`<button class="settings-category" data-edit-category="${escape(c.id)}"><span class="category-dot" style="background:${c.color}"></span>${escape(c.name)}${c.important?' ★':''}<span>Edit ↗</span></button>`).join('');
  const zones=[...new Set([tz,'Europe/Berlin','UTC',...(Intl.supportedValuesOf?Intl.supportedValuesOf('timeZone'):['Europe/London','America/New_York','America/Los_Angeles','Asia/Tokyo'])])];
  $('timezone').innerHTML=zones.map(z=>`<option value="${escape(z)}">${escape(z.replaceAll('_',' '))}</option>`).join('');$('timezone').value=tz;
}
function openSettings(){renderSettings();if(!$('settings-dialog').open)$('settings-dialog').showModal();}
function openCategory(id=null){
  if(categories.length>=30&&!id){toast('You can have up to 30 categories.');return;}
  editedCategory=id;const c=categories.find(c=>c.id===id);$('category-edit-title').textContent=c?'Edit category':'New category';$('category-name').value=c?.name||'';$('category-important').checked=!!c?.important;$('category-keywords').value=c?.keywords.join(', ')||'';$('delete-category').hidden=!c;
  $('category-dialog').showModal();
}
function openAdd(id){
  if(!validSession()){openSettings();toast('Connect Google Calendar before adding a block.');return;}
  if(!categories.length){openSettings();toast('Create a category first.');return;}
  pendingSave=null;$('add-category').innerHTML=options();$('add-category').value=categories.some(c=>c.id===id)?id:categories[0].id;$('add-title').value='';$('add-start').value=dateParts(Date.now(),tz).slice(0,16);$('add-duration').value='30';$('start-timezone').textContent=tz;
  const writable=calendars.filter(c=>['owner','writer'].includes(c.accessRole));$('add-calendar').innerHTML=writable.map(c=>`<option value="${escape(c.id)}">${escape(c.summary||c.id)}</option>`).join('');
  if(writable.some(c=>c.id===selectedWriteCalendar))$('add-calendar').value=selectedWriteCalendar;else $('add-calendar').value=(writable.find(c=>c.primary)||writable[0])?.id||'';
  $('add-error').textContent=writable.length?'':'This Google account has no writable calendars.';$('save-block').disabled=!writable.length;$('save-block').textContent='Save to Google Calendar';$('check-save').hidden=true;$('saved-event-link').hidden=true;preview();$('add-dialog').showModal();
}
function draft(){const category=$('add-category').value;if(!categories.some(c=>c.id===category))throw new Error('Choose a category.');const calendarId=$('add-calendar').value;if(!calendars.some(c=>c.id===calendarId&&['owner','writer'].includes(c.accessRole)))throw new Error('Choose a writable calendar.');return {calendarId,event:makeEventDraft({title:$('add-title').value,category,start:$('add-start').value,duration:Number($('add-duration').value),tz})};}
function preview(){
  document.querySelectorAll('[data-duration]').forEach(b=>b.classList.toggle('active',b.dataset.duration===$('add-duration').value));
  $('preview-title').textContent=$('add-title').value.trim()||'Choose a concrete action';
  try{const d=makeEventDraft({title:'Preview',category:$('add-category').value,start:$('add-start').value,duration:Number($('add-duration').value),tz});$('preview-time').textContent=fmtDate(Date.parse(d.start.dateTime),{weekday:'short'})+' · '+fmtTime(Date.parse(d.start.dateTime))+'–'+fmtTime(Date.parse(d.end.dateTime))+' · '+cat($('add-category').value).name;}catch{$('preview-time').textContent='Choose a valid start time and duration.';}
}
function lockForm(locked){[...$('add-form').elements].forEach(el=>el.disabled=locked);$('save-block').textContent=locked?'Saving…':'Save to Google Calendar';}
async function saved(raw,calendarId){
  const c=calendars.find(c=>c.id===calendarId),event=normalizeEvent(raw,c);if(event){events=events.filter(e=>e.key!==event.key);events.push(event);}
  if(!selected.includes(calendarId))selected.push(calendarId);selectedWriteCalendar=calendarId;persist();render();renderSettings();
  const url=safeGoogleLink(raw.htmlLink);$('saved-event-link').hidden=!url;if(url)$('saved-event-link').href=url;
  $('check-save').hidden=true;$('add-error').textContent='Saved to Google Calendar.';$('add-title').value='';pendingSave=null;toast('Saved to Google Calendar. Scheduled time is separate from elapsed time.');
  await sync();
}
async function saveBlock(evt){
  evt.preventDefault();if(saving)return;if(pendingSave?.uncertain){toast('Check the previous save before creating another block.');return;}
  let payload;try{payload=draft();}catch(err){$('add-error').textContent=err.message;return;}
  if(!validSession()){invalidate();$('add-error').textContent='Reconnect Google Calendar, then review and save your block again.';return;}
  saving=true;lockForm(true);$('add-error').textContent='';const owner=account;
  try{
    if(!writeGranted){await authorize(READ_SCOPES+' '+WRITE_SCOPE);const list=await listCalendars(token);const current=(list.find(c=>c.primary)||list[0])?.id;if(current!==owner){invalidate();throw new Error('Google account changed. Reconnect and review the destination calendar before saving.');}}
    const id='tl'+crypto.randomUUID().replaceAll('-','');pendingSave={...payload,event:{...payload.event,id},uncertain:false};
    const raw=await createEvent(token,payload.calendarId,pendingSave.event);await saved(raw,payload.calendarId);
  }catch(err){
    if(err.uncertain||err.status===409){if(pendingSave){pendingSave.uncertain=true;$('check-save').hidden=false;}$('add-error').textContent='The save could not be confirmed. Check its status before creating another block.';}
    else{pendingSave=null;$('add-error').textContent=err.message;if(err.status===401)invalidate();}
  }finally{saving=false;lockForm(false);if(pendingSave?.uncertain)$('save-block').disabled=true;}
}
async function checkSave(){
  if(!pendingSave||saving)return;if(!validSession()){toast('Reconnect to check this event in Google Calendar.');return;}
  saving=true;$('check-save').disabled=true;
  try{const raw=await calendarRequest(token,eventPath(pendingSave.calendarId,pendingSave.event.id));await saved(raw,pendingSave.calendarId);$('save-block').disabled=false;}
  catch(err){if(err.status===404){pendingSave=null;$('check-save').hidden=true;$('save-block').disabled=false;$('add-error').textContent='Google has no event with this ID. Review the draft and save again.';}else $('add-error').textContent=err.message;}
  finally{saving=false;$('check-save').disabled=false;}
}
function openEvent(key){editedEvent=events.find(e=>e.key===key);if(!editedEvent)return;$('event-detail-title').textContent=editedEvent.title;$('event-detail-time').textContent=fmtDate(editedEvent.start,{weekday:'short'})+' · '+fmtTime(editedEvent.start)+'–'+fmtTime(editedEvent.end)+' · '+editedEvent.calendarName;$('event-category').innerHTML=options(true);$('event-category').value=allocate([editedEvent],{start:editedEvent.start,end:editedEvent.end,now:editedEvent.end},categories,assignments,series).elapsed[0].category;$('apply-series').checked=false;$('series-label').hidden=!editedEvent.seriesKey;$('event-dialog').showModal();}
document.addEventListener('click',event=>{
  const close=event.target.closest('[data-close]');if(close){close.closest('dialog').close();return;}
  const add=event.target.closest('[data-add],[data-add-category]');if(add){openAdd(add.dataset.addCategory);return;}
  const category=event.target.closest('[data-filter]');if(category){filter=category.dataset.filter;render();document.querySelector('.transactions').scrollIntoView({behavior:'smooth',block:'start'});return;}
  const edit=event.target.closest('[data-edit-category]');if(edit){openCategory(edit.dataset.editCategory);return;}
  const entry=event.target.closest('[data-event]');if(entry){openEvent(entry.dataset.event);return;}
  if(event.target.closest('[data-connect]'))connect();if(event.target.closest('[data-settings]'))openSettings();
});
document.querySelectorAll('dialog').forEach(d=>d.addEventListener('click',evt=>{if(evt.target===d){const r=d.getBoundingClientRect();if(evt.clientX<r.left||evt.clientX>r.right||evt.clientY<r.top||evt.clientY>r.bottom)d.close();}}));
$('today-button').onclick=()=>{period='today';render();};$('week-button').onclick=()=>{period='week';render();};$('past-events').onclick=()=>{scheduled=false;render();};$('future-events').onclick=()=>{scheduled=true;render();};$('clear-filter').onclick=()=>{filter=null;render();};
$('source-button').onclick=()=>connected?openSettings():connect();$('connect-button').onclick=connect;$('disconnect-button').onclick=disconnect;$('settings-button').onclick=openSettings;$('calendar-nav').onclick=openSettings;$('manage-categories').onclick=openSettings;$('new-category').onclick=()=>openCategory();$('method-button').onclick=()=>$('method-dialog').showModal();$('refresh-button').onclick=sync;
$('overview-nav').onclick=()=>window.scrollTo({top:0,behavior:'smooth'});
$('calendar-list').onchange=e=>{const id=e.target.dataset.calendar;if(!id)return;selected=e.target.checked?[...new Set([...selected,id])]:selected.filter(c=>c!==id);persist();sync();};
$('timezone').onchange=()=>{tz=$('timezone').value;persist();render();sync();};
$('category-form').onsubmit=e=>{
  e.preventDefault();const name=$('category-name').value.trim();if(!name){$('category-name').setCustomValidity('Enter a category name.');$('category-name').reportValidity();return;}
  if(categories.some(c=>c.id!==editedCategory&&c.name.toLowerCase()===name.toLowerCase())||[UNCLASSIFIED.name,CONFLICT.name].some(n=>n.toLowerCase()===name.toLowerCase())){toast('Choose a unique category name.');return;}
  const keywords=$('category-keywords').value.split(',').map(s=>s.trim().toLowerCase()).filter(Boolean).slice(0,50);
  const current=categories.find(c=>c.id===editedCategory),next={id:editedCategory||crypto.randomUUID(),name,important:$('category-important').checked,keywords,color:current?.color||['#2f60ed','#42a995','#8c79d2','#d3a052','#d17fa1'][categories.length%5]};
  categories=current?categories.map(c=>c.id===next.id?next:c):[...categories,next];persist();$('category-dialog').close();render();renderSettings();
};
$('category-name').oninput=()=>$('category-name').setCustomValidity('');
$('delete-category').onclick=()=>{if(!editedCategory)return;const id=editedCategory;categories=categories.filter(c=>c.id!==id);for(const [k,v] of Object.entries(assignments))if(v===id)delete assignments[k];for(const [k,v] of Object.entries(series))if(v===id)delete series[k];if(filter===id)filter=null;persist();$('category-dialog').close();render();renderSettings();};
$('save-event-category').onclick=()=>{if(!editedEvent)return;const category=$('event-category').value;assignments[editedEvent.key]=category;if($('apply-series').checked&&editedEvent.seriesKey){series[editedEvent.seriesKey]=category;for(const e of events)if(e.seriesKey===editedEvent.seriesKey)delete assignments[e.key];}persist();$('event-dialog').close();render();toast('Category choice saved.');};
$('add-form').onsubmit=saveBlock;$('check-save').onclick=checkSave;
['add-title','add-start','add-duration','add-category'].forEach(id=>$(id).addEventListener('input',preview));
document.querySelectorAll('[data-duration]').forEach(b=>b.onclick=()=>{$('add-duration').value=b.dataset.duration;preview();});$('start-now').onclick=()=>{$('add-start').value=dateParts(Date.now(),tz).slice(0,16);preview();};
document.addEventListener('visibilitychange',()=>{if(!document.hidden){render();if(validSession()&&(!lastSync||Date.now()-lastSync>60000)&&!busy&&!saving)sync();}});
setInterval(()=>{if(!saving)render();},30000);
render();renderSettings();
