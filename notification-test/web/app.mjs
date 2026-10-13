import {GOOGLE_CLIENT_ID} from './config.mjs';
import {todayBounds,localStamp,accountDay,normalize,duration,makeGapEvent} from './timeline.mjs';
import {READ_SCOPES,WRITE_SCOPE,listCalendars,listEvents,createEvent,deleteEvent,calendarRequest,eventPath} from './google.mjs';

const $=id=>document.getElementById(id);
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
let token=null,expires=0,writeGranted=false,account=null,calendars=[],selected=[],events=[],lastRead=null,ready=false,busy=false,saving=false,gap=null,pending=null;
let deletingEvent=null,pendingDelete=null;
const valid=()=>Boolean(token&&Date.now()<expires);
const fmt=ms=>new Intl.DateTimeFormat('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit'}).format(ms);
const prefsKey=()=>`time-ledger:today:calendars:${account}`;
const pendingKey=()=>`time-ledger:today:pending:${account}`;
const deleteKey=()=>`time-ledger:today:pending-delete:${account}`;
const writable=()=>calendars.filter(c=>['owner','writer'].includes(c.accessRole));
const message=(text,error=false)=>{$('message').textContent=text;$('message').hidden=!text;$('message').classList.toggle('error',error);};
function savePrefs(){try{localStorage.setItem(prefsKey(),JSON.stringify(selected));}catch{/* Calendar events remain saved at Google even if device preferences are unavailable. */}}
function persistPending(){try{if(pending)sessionStorage.setItem(pendingKey(),JSON.stringify(pending));else sessionStorage.removeItem(pendingKey());}catch{if(pending)message('Keep this app open until the save is confirmed. This browser could not store its recovery details.',true);}}
function persistDelete(){try{if(pendingDelete)sessionStorage.setItem(deleteKey(),JSON.stringify(pendingDelete));else sessionStorage.removeItem(deleteKey());}catch{if(pendingDelete)message('Keep this app open until the deletion is confirmed. Its recovery details could not be stored.',true);}}
function loadPrefs(){
  let stored;try{stored=JSON.parse(localStorage.getItem(prefsKey()));}catch{}
  selected=Array.isArray(stored)?stored.filter(id=>calendars.some(c=>c.id===id)):calendars.filter(c=>c.selected!==false||c.primary).map(c=>c.id);
  pending=null;try{const p=JSON.parse(sessionStorage.getItem(pendingKey()));if(p&&typeof p.calendarId==='string'&&/^tl[0-9a-f]{32}$/.test(p.event?.id)&&calendars.some(c=>c.id===p.calendarId)&&typeof p.event.summary==='string'&&p.event.start?.dateTime&&p.event.end?.dateTime)pending=p;}catch{}
  pendingDelete=null;deletingEvent=null;try{const p=JSON.parse(sessionStorage.getItem(deleteKey()));if(p&&typeof p.id==='string'&&p.id.length<=1024&&typeof p.title==='string'&&calendars.some(c=>c.id===p.calendarId))pendingDelete=p;}catch{}
}
function authorization(scopes){
  return new Promise((resolve,reject)=>{
    if(!window.google?.accounts?.oauth2)return reject(new Error('Google sign-in is still loading or was blocked. Wait a moment and try again. If needed, open this app in Safari.'));
    const oauth=google.accounts.oauth2;
    const client=oauth.initTokenClient({client_id:GOOGLE_CLIENT_ID,scope:scopes,include_granted_scopes:true,...(account?.includes('@')?{hint:account}:{}),callback:r=>{
      if(r.error)return reject(new Error(r.error_description||'Google authorization was not completed.'));
      if(!oauth.hasGrantedAllScopes(r,...scopes.split(' ')))return reject(new Error('Grant the requested Calendar permissions in Google’s consent screen.'));
      token=r.access_token;expires=Date.now()+Number(r.expires_in||3600)*1000-30000;
      writeGranted=oauth.hasGrantedAllScopes(r,WRITE_SCOPE);resolve();
    },error_callback:e=>reject(new Error(e.type==='popup_closed'?'Google sign-in was closed.':'Google sign-in could not open. Try connecting in Safari at this same address.'))});
    client.requestAccessToken({prompt:account?'':'select_account'});
  });
}
function renderSettings(){
  $('calendar-list').innerHTML=calendars.map(c=>`<label class="calendar-choice"><input type="checkbox" data-calendar="${escape(c.id)}" ${selected.includes(c.id)?'checked':''} ${busy||saving?'disabled':''}><span>${escape(c.summary||c.id)}${c.primary?' · Primary':''}</span></label>`).join('');
  $('connection-state').textContent=valid()?'Connected directly to Google Calendar.':account?'Your Google session expired. Reconnect to refresh or save.':'Connect Google Calendar to load your day.';
  $('reconnect').disabled=busy||saving;$('disconnect').disabled=busy||saving;
}
function deleteControl(event){
  if(!writable().some(c=>c.id===event.calendarId))return '<span class="read-only">Read only</span>';
  return `<button class="event-delete" data-delete="${escape(JSON.stringify([event.calendarId,event.id]))}" aria-label="Delete event: ${escape(event.title)}" ${busy||saving||pending||pendingDelete||!valid()?'disabled':''}>Delete</button>`;
}
function render(){
  const now=Date.now();
  $('date').textContent=new Intl.DateTimeFormat('en-GB',{timeZone:tz,weekday:'long',day:'numeric',month:'long'}).format(now);
  $('zone').textContent=tz.replaceAll('_',' ');
  $('welcome').hidden=!!account;$('day').hidden=!account;$('settings').hidden=!account;
  $('connect').disabled=busy;$('connect').textContent=busy?'Connecting…':'Connect Google Calendar';
  $('loading').hidden=!busy;$('refresh').disabled=busy||saving;
  $('refresh').textContent=valid()?'Refresh':'Reconnect';
  $('recover').hidden=!pending||!account;$('recover').disabled=busy||saving;
  $('recover-delete').hidden=!pendingDelete||!account;$('recover-delete').disabled=busy||saving;
  document.querySelector('.summary').hidden=!ready;
  if(!ready){$('timeline').replaceChildren();$('now').hidden=true;$('all-day').hidden=true;renderSettings();return;}
  const bounds=todayBounds(lastRead,tz),data=accountDay(events,bounds);
  $('recorded').textContent=duration(data.recorded);$('missing').textContent=duration(data.missing);
  $('missing').classList.toggle('complete',!data.missing);
  $('progress').style.width=(data.elapsed?data.recorded/data.elapsed*100:0)+'%';
  $('summary-note').textContent=data.missing?`${duration(data.elapsed)} since midnight · ${data.gaps.length} gap${data.gaps.length===1?'':'s'} to fill.`:'Every moment so far is recorded.';
  $('fill-first').hidden=!data.gaps.length;$('fill-first').disabled=busy||saving||!!pending||!!pendingDelete||!valid();
  $('timeline').innerHTML=data.segments.map((s,i)=>`<div class="row"><div class="time">${fmt(s.start)}<span>${fmt(s.end)}</span></div>${s.kind==='gap'?`<button class="entry gap" data-gap="${i}" ${busy||saving||pending||pendingDelete||!valid()?'disabled':''}><span class="plus" aria-hidden="true">＋</span><h3>What were you doing?</h3><p>${escape(duration(s.end-s.start))} unrecorded · Tap to fill in</p></button>`:`<div class="entry">${s.events.map((e,j)=>`<div ${j?'class="overlap"':''}><div class="event-head"><h3>${escape(e.title)}</h3>${deleteControl(e)}</div><p>${escape(e.calendarName)}</p></div>`).join('')}<p>${escape(duration(s.end-s.start))}${s.events.length>1?' · Overlap counted once':''}</p></div>`}</div>`).join('');
  $('now').hidden=false;$('now').textContent=`As of ${fmt(lastRead)}${valid()?'':' · Reconnect to update'}`;
  $('all-day').hidden=!data.allDay.length;$('all-day-label').textContent=`${data.allDay.length} all-day event${data.allDay.length===1?'':'s'}`;
  $('all-day-list').innerHTML=data.allDay.map(e=>`<li><div class="event-head"><span>${escape(e.title)} · ${escape(e.calendarName)}</span>${deleteControl(e)}</div></li>`).join('');
  renderSettings();
}
async function connect(){
  if(busy||saving)return;busy=true;render();message('');
  try{
    await authorization(READ_SCOPES);const list=await listCalendars(token),identity=(list.find(c=>c.primary)||list[0])?.id;
    if(!identity)throw new Error('No calendars are available for this Google account.');
    account=identity;calendars=list;events=[];ready=false;lastRead=null;loadPrefs();
    busy=false;await sync();
  }catch(e){token=null;expires=0;busy=false;message(e.message,true);render();}
}
async function sync(){
  if(!valid()){message('Reconnect Google Calendar to refresh your day.',true);render();return false;}
  if(busy)return false;
  busy=true;ready=false;render();const captured=Date.now(),bounds=todayBounds(captured,tz),ids=[...selected];
  try{
    if(!ids.length)throw new Error('Choose at least one calendar in Calendars.');
    const results=await Promise.allSettled(ids.map(async id=>({calendar:calendars.find(c=>c.id===id),rows:await listEvents(token,id,bounds.start,bounds.end)})));
    const failures=results.map((r,i)=>r.status==='rejected'?`${calendars.find(c=>c.id===ids[i])?.summary||'Calendar'}: ${r.reason.message}`:null).filter(Boolean);
    if(failures.length)throw new Error('Could not read all selected calendars. Refresh before filling gaps. '+failures.join(' '));
    events=results.flatMap(r=>r.value.rows.map(raw=>normalize(raw,r.value.calendar)).filter(Boolean));lastRead=captured;ready=true;message('');return true;
  }catch(e){message(e.message,true);return false;}
  finally{busy=false;render();}
}
function openGap(index){
  if(!ready||busy||saving||pending||pendingDelete||!valid())return;
  const bounds=todayBounds(lastRead,tz);gap=accountDay(events,bounds).segments[index];if(!gap||gap.kind!=='gap')return;
  $('activity').value='';$('start').value=localStamp(gap.start,tz);$('end').value=localStamp(gap.end,tz);
  $('start').min=$('end').min=localStamp(gap.start,tz);$('start').max=$('end').max=localStamp(gap.end,tz);
  $('gap-caption').textContent=`${fmt(gap.start)}–${fmt(gap.end)} · ${duration(gap.end-gap.start)} unrecorded`;
  const choices=writable();$('destination').innerHTML=choices.map(c=>`<option value="${escape(c.id)}">${escape(c.summary||c.id)}</option>`).join('');
  $('destination').value=(choices.find(c=>selected.includes(c.id)&&c.primary)||choices.find(c=>selected.includes(c.id))||choices.find(c=>c.primary)||choices[0])?.id||'';
  $('save-error').textContent=choices.length?'':'Your Google account has no writable calendars.';$('check').hidden=true;
  lockForm(false);$('gap-dialog').showModal();
}
function lockForm(locked){
  [...$('gap-form').elements].forEach(el=>el.disabled=locked);
  $('save').disabled=locked||!!pending||!writable().length;
  $('check').disabled=locked;$('save').textContent=locked?'Saving…':'Save to Google Calendar';
  $('gap-dialog').querySelector('[data-close]').disabled=locked;
}
async function confirmAccount(){
  const list=await listCalendars(token),identity=(list.find(c=>c.primary)||list[0])?.id;
  if(identity!==account){token=null;expires=0;writeGranted=false;events=[];ready=false;throw new Error('The Google account changed. Reconnect and review your calendars before saving.');}
  calendars=list;
}
async function confirmed(raw,calendarId){
  if(!raw.id||raw.status==='cancelled')throw new Error('Google did not confirm a saved event.');
  pending=null;persistPending();if(!selected.includes(calendarId)){selected.push(calendarId);savePrefs();}
  $('gap-dialog').close();const ok=await sync();
  if(ok)message('Saved to Google Calendar.');else message('Saved to Google Calendar, but the refreshed timeline could not load. Tap Refresh before filling another gap.',true);
}
async function saveGap(e){
  e.preventDefault();if(saving||busy||pending||pendingDelete)return;
  const calendarId=$('destination').value;let draft;
  try{
    if(!valid())throw new Error('Reconnect Google Calendar before saving. Your activity has not been saved.');
    if(!writable().some(c=>c.id===calendarId))throw new Error('Choose a writable calendar.');
    draft=makeGapEvent({title:$('activity').value,start:$('start').value,end:$('end').value,gap,bounds:todayBounds(Date.now(),tz),tz,id:makeId()});
  }catch(err){$('save-error').textContent=err.message;return;}
  saving=true;lockForm(true);$('save-error').textContent='';render();
  try{
    // Open Google’s permission popup directly from this user action, before any reads.
    if(!writeGranted){await authorization(READ_SCOPES+' '+WRITE_SCOPE);await confirmAccount();}
    if(!await sync())throw new Error('The calendar could not be refreshed. Try again before saving.');
    const start=Date.parse(draft.start.dateTime),end=Date.parse(draft.end.dateTime),current=accountDay(events,todayBounds(lastRead,tz));
    if(!current.gaps.some(g=>g.start<=start&&g.end>=end))throw new Error('Your calendar changed and this time is no longer empty. Close this form and review the refreshed day.');
    if(!writable().some(c=>c.id===calendarId))throw new Error('This calendar is no longer writable. Choose another calendar.');
    pending={calendarId,event:draft};persistPending();
    const raw=await createEvent(token,calendarId,draft);await confirmed(raw,calendarId);
  }catch(err){
    if(pending&&(err.uncertain||err.status===409)){$('check').hidden=false;$('save-error').textContent='The save could not be confirmed. Check whether it saved before creating another event.';}
    else{pending=null;persistPending();$('save-error').textContent=err.message;}
  }finally{saving=false;lockForm(false);render();}
}
async function checkSave(){
  if(!pending||saving||busy)return;saving=true;lockForm(true);render();
  try{
    if(!valid())await authorization(READ_SCOPES);
    await confirmAccount();
    const raw=await calendarRequest(token,eventPath(pending.calendarId,pending.event.id));
    if(raw.status==='cancelled')throw new Error('That event was deleted in Google Calendar. Check your calendar before recording this time again.');
    await confirmed(raw,pending.calendarId);
  }catch(e){
    // Keep the same ID if Google has no event yet: retrying cannot create a second copy.
    if(e.status===404){
      const draft=pending;const ok=await sync();
      if(!ok){message('Could not check today’s timeline. Refresh and check this save again.',true);return;}
      const start=Date.parse(draft.event.start.dateTime),end=Date.parse(draft.event.end.dateTime);
      if(!accountDay(events,todayBounds(lastRead,tz)).gaps.some(g=>g.start<=start&&g.end>=end)){message('Google has no event with this ID, but this time is now recorded. Review your calendar before retrying.',true);return;}
      // A retry is a separate, explicit user action with the original event ID.
      $('gap-caption').textContent='This save was not found. Review the activity and save it again.';
      $('activity').value=draft.event.summary;$('start').value=localStamp(start,tz);$('end').value=localStamp(end,tz);
      gap={start,end};$('destination').innerHTML=writable().map(c=>`<option value="${escape(c.id)}">${escape(c.summary||c.id)}</option>`).join('');$('destination').value=draft.calendarId;
      $('start').min=$('end').min=localStamp(start,tz);$('start').max=$('end').max=localStamp(end,tz);
      retryDraft=draft;pending=null;persistPending();$('check').hidden=true;$('save-error').textContent='Not found in Google Calendar. Review and save again.';
      if(!$('gap-dialog').open)$('gap-dialog').showModal();
    }else{message(e.message,true);$('save-error').textContent=e.message;}
  }finally{saving=false;lockForm(false);render();}
}
let retryDraft=null;
function showDeleteEvent(event){
  deletingEvent=event;$('delete-name').textContent=event.title;
  const dateTime=ms=>new Intl.DateTimeFormat('en-GB',{timeZone:tz,day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(ms);
  $('delete-caption').textContent=event.calendarName+' · '+(event.allDay?'All day · '+event.startDate:dateTime(event.start)+' – '+dateTime(event.end));
  $('delete-recurring').hidden=!event.recurring;$('delete-guests').hidden=!event.hasGuests;
}
function openDelete(reference){
  if(!ready||busy||saving||pending||pendingDelete||!valid())return;
  let ids;try{ids=JSON.parse(reference);}catch{return;}
  const event=events.find(e=>e.calendarId===ids[0]&&e.id===ids[1]);
  if(!event||!writable().some(c=>c.id===event.calendarId))return;
  showDeleteEvent(event);$('delete-error').textContent='';$('delete-check').hidden=true;lockDelete(false);$('delete-dialog').showModal();
}
function lockDelete(locked){
  $('delete-confirm').disabled=locked||!!pendingDelete;
  $('delete-confirm').textContent=locked?'Deleting…':'Delete from Google Calendar';
  $('delete-check').disabled=locked;$('delete-cancel').disabled=locked;
  $('delete-dialog').querySelector('[data-close]').disabled=locked;
}
async function deletionConfirmed(target){
  pendingDelete=null;persistDelete();deletingEvent=null;
  events=events.filter(e=>!(e.calendarId===target.calendarId&&e.id===target.id));
  $('delete-dialog').close();const ok=await sync();
  message(ok?'Removed from Google Calendar. Any uncovered time is now a gap.':'Removed from Google Calendar. Refresh the timeline before filling any new gaps.',!ok);
}
async function confirmDelete(){
  if(saving||busy||pending||pendingDelete||!deletingEvent||!valid())return;
  const target=deletingEvent;
  if(!writable().some(c=>c.id===target.calendarId))return;
  saving=true;lockDelete(true);$('delete-error').textContent='';render();
  try{
    if(!writeGranted)await authorization(READ_SCOPES+' '+WRITE_SCOPE);
    await confirmAccount();
    if(!writable().some(c=>c.id===target.calendarId))throw new Error('You no longer have permission to delete events from this calendar.');
    const raw=await calendarRequest(token,eventPath(target.calendarId,target.id));
    if(raw.status==='cancelled'){await deletionConfirmed(target);return;}
    const fresh=normalize(raw,calendars.find(c=>c.id===target.calendarId));
    if(!fresh)throw new Error('This event is no longer available. Refresh your day.');
    if((target.etag&&raw.etag!==target.etag)||fresh.title!==target.title||fresh.start!==target.start||fresh.end!==target.end||fresh.startDate!==target.startDate||fresh.endDate!==target.endDate)throw new Error('This event changed in Google Calendar. Close this dialog, refresh, and review it before deleting.');
    pendingDelete={calendarId:target.calendarId,id:target.id,title:target.title};persistDelete();
    await deleteEvent(token,target.calendarId,target.id,raw.etag);await deletionConfirmed(target);
  }catch(e){
    if(e.status===404||e.status===410){await deletionConfirmed(target);}
    else if(e.uncertain){$('delete-error').textContent='Deletion could not be confirmed. Check its status before trying again.';$('delete-check').hidden=false;}
    else{pendingDelete=null;persistDelete();$('delete-error').textContent=e.message;}
  }finally{saving=false;lockDelete(false);render();}
}
async function checkDeletion(){
  if(!pendingDelete||saving||busy)return;
  const target=pendingDelete;saving=true;lockDelete(true);render();
  try{
    if(!valid())await authorization(READ_SCOPES);
    await confirmAccount();
    const raw=await calendarRequest(token,eventPath(target.calendarId,target.id));
    if(raw.status==='cancelled'){await deletionConfirmed(target);return;}
    const fresh=normalize(raw,calendars.find(c=>c.id===target.calendarId));
    if(!fresh)throw new Error('The deletion status could not be determined. Check Google Calendar and try again.');
    pendingDelete=null;persistDelete();showDeleteEvent(fresh);$('delete-check').hidden=true;
    $('delete-error').textContent='Google still has this event. Review it and tap Delete to try again.';
    if(!$('delete-dialog').open)$('delete-dialog').showModal();
  }catch(e){
    if(e.status===404||e.status===410)await deletionConfirmed(target);
    else{message(e.message,true);$('delete-error').textContent=e.message;}
  }finally{saving=false;lockDelete(false);render();}
}
// Reuse a recovered event ID until that exact draft is either saved or dismissed.
const makeId=()=>retryDraft?.event.id||'tl'+crypto.randomUUID().replaceAll('-','');
$('gap-form').onsubmit=saveGap;$('check').onclick=checkSave;$('recover').onclick=checkSave;
$('delete-confirm').onclick=confirmDelete;$('delete-check').onclick=checkDeletion;$('recover-delete').onclick=checkDeletion;
$('connect').onclick=connect;$('reconnect').onclick=async()=>{await connect();};
$('refresh').onclick=()=>valid()?sync():connect();
$('settings').onclick=()=>{renderSettings();$('settings-dialog').showModal();};
$('disconnect').onclick=()=>{
  const old=token;token=null;expires=0;account=null;writeGranted=false;calendars=[];events=[];selected=[];lastRead=null;ready=false;pending=null;retryDraft=null;pendingDelete=null;deletingEvent=null;
  $('settings-dialog').close();message('Disconnected. Loaded Calendar data has been cleared.');render();
  if(old&&window.google?.accounts?.oauth2)google.accounts.oauth2.revoke(old,()=>{});
};
$('calendar-list').onchange=async e=>{
  const id=e.target.dataset.calendar;if(!id||busy||saving)return;
  selected=e.target.checked?[...new Set([...selected,id])]:selected.filter(x=>x!==id);savePrefs();await sync();
};
$('fill-first').onclick=()=>{const data=accountDay(events,todayBounds(lastRead,tz));openGap(data.segments.findIndex(s=>s.kind==='gap'));};
document.addEventListener('click',e=>{
  const close=e.target.closest('[data-close]');if(close){close.closest('dialog').close();return;}
  const remove=e.target.closest('[data-delete]');if(remove){openDelete(remove.dataset.delete);return;}
  const button=e.target.closest('[data-gap]');if(button){retryDraft=null;openGap(Number(button.dataset.gap));}
});
$('gap-dialog').addEventListener('cancel',e=>{if(saving)e.preventDefault();});
$('gap-dialog').addEventListener('close',()=>{if(!pending)retryDraft=null;});
$('delete-dialog').addEventListener('cancel',e=>{if(saving)e.preventDefault();});
$('delete-dialog').addEventListener('close',()=>{if(!pendingDelete)deletingEvent=null;});
document.addEventListener('visibilitychange',()=>{if(!document.hidden){render();if(valid()&&!busy&&!saving&&!$('gap-dialog').open&&!$('delete-dialog').open)sync();}});
setInterval(()=>{if(!document.hidden&&!busy&&!saving&&!$('gap-dialog').open&&!$('delete-dialog').open){if(valid())sync();else render();}},60000);
if('serviceWorker' in navigator)navigator.serviceWorker.register('/sw.js',{scope:'/'}).catch(()=>{});
render();
