import {GOOGLE_CLIENT_ID} from './config.mjs';
import {todayBounds,localStamp,localToMs,accountDay,normalize,duration,makeGapEvent,formatTime} from './timeline.mjs';
import {READ_SCOPES,WRITE_SCOPE,listCalendars,listEvents,createEvent,deleteEvent,calendarRequest,eventPath} from './google.mjs';
import {categoryName,categoryPlan,renamePlans,CategoryJournal,sameState} from './categories.mjs';

const $=id=>document.getElementById(id);
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tz=Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC';
let token=null,expires=0,writeGranted=false,account=null,calendars=[],selected=[],events=[],lastRead=null,ready=false,busy=false,saving=false,gap=null,pending=null;
let deletingEvent=null,pendingDelete=null;
let categories=[],categoryPlans=[],categoryMeta={},renameCategoryId=null;
const categoryDefsKey=()=>`time-ledger:today:categories:${account}`;
const journal=()=>new CategoryJournal(localStorage,account);
function persistCategories(){localStorage.setItem(categoryDefsKey(),JSON.stringify(categories));}
const timeFormatKey='time-ledger:today:time-format';
let timeFormat='24';try{if(localStorage.getItem(timeFormatKey)==='12')timeFormat='12';}catch{}
const valid=()=>Boolean(token&&Date.now()<expires);
const fmt=ms=>formatTime(ms,tz,timeFormat);
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
  categories=[{id:'work',name:'Work'},{id:'personal',name:'Personal'},{id:'sleep',name:'Sleep'}];
  try{const c=JSON.parse(localStorage.getItem(categoryDefsKey()));if(Array.isArray(c)&&c.every(x=>typeof x.id==='string'&&typeof x.name==='string'))categories=c;}catch{}
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
  $('time-format').value=timeFormat;$('calendar-settings').hidden=!account;
  $('calendar-list').innerHTML=calendars.map(c=>`<label class="calendar-choice"><input type="checkbox" data-calendar="${escape(c.id)}" ${selected.includes(c.id)?'checked':''} ${busy||saving?'disabled':''}><span>${escape(c.summary||c.id)}${c.primary?' · Primary':''}</span></label>`).join('');
  $('connection-state').textContent=valid()?'Connected directly to Google Calendar.':account?'Your Google session expired. Reconnect to refresh or save.':'Connect Google Calendar to load your day.';
  $('reconnect').disabled=busy||saving;$('disconnect').disabled=busy||saving;
  $('category-list').innerHTML=categories.map(c=>`<div class="category-setting"><span>${escape(c.name)}</span><button class="text-button" data-rename-category="${escape(c.id)}" ${busy||saving?'disabled':''}>Rename</button></div>`).join('');
  $('category-add').disabled=busy||saving||!account;
  try{const records=account?journal().read():[];$('undo-category').disabled=busy||saving||!records.some(b=>b.items.some(i=>i.status==='applied'));$('check-category').hidden=!records.some(b=>b.items.some(i=>['prepared','uncertain','undoing'].includes(i.status)));}catch(e){$('category-status').textContent=e.message;}
  $('check-category').disabled=busy||saving;
}
function deleteControl(event){
  if(!writable().some(c=>c.id===event.calendarId))return '<span class="read-only">Read only</span>';
  return `<button class="event-delete" data-delete="${escape(JSON.stringify([event.calendarId,event.id]))}" aria-label="Delete event: ${escape(event.title)}" ${busy||saving||pending||pendingDelete||!valid()?'disabled':''}>Delete</button>`;
}
const pixelsPerMinute=1.25;
const gridPosition=(at,bounds)=>(at-bounds.start)/60000*pixelsPerMinute;
function ledgerGrid(data,bounds){
  const noon=localToMs(bounds.date+'T12:00',tz),lines=[];
  for(let at=bounds.start;at<=bounds.end;at+=3600000){
    const isNoon=at===noon;
    lines.push(`<div class="hour-line${isNoon?' noon-line':''}${at===bounds.start?' first-hour':''}" style="top:${gridPosition(at,bounds)}px" ${isNoon?'role="separator" aria-label="Noon"':'aria-hidden="true"'}><span class="hour-label">${fmt(at)}</span><span class="grid-rule"></span>${isNoon?'<span class="noon-label">Noon</span>':''}</div>`);
  }
  // In zones with a fractional-hour clock change, local noon may fall between grid ticks.
  if(noon<=bounds.end&&!lines.some(line=>line.includes('noon-line')))lines.push(`<div class="hour-line noon-line" style="top:${gridPosition(noon,bounds)}px" role="separator" aria-label="Noon"><span class="hour-label">${fmt(noon)}</span><span class="grid-rule"></span><span class="noon-label">Noon</span></div>`);
  const blocks=data.segments.map((s,i)=>{
    const height=(s.end-s.start)/60000*pixelsPerMinute,size=height>=56?' tall':height>=32?' medium':' tiny';
    const style=`top:${gridPosition(s.start,bounds)}px;height:${height}px`;
    const label=`${fmt(s.start)}–${fmt(s.end)} · ${duration(s.end-s.start)}`;
    if(s.kind==='gap')return `<button class="entry gap grid-block${size}" data-gap="${i}" style="${style}" aria-label="Unrecorded time: ${escape(label)}. Fill this gap." ${busy||saving||pending||pendingDelete||!valid()?'disabled':''}><h3>${height>=56?'What were you doing?':'Unrecorded'}</h3><p>${escape(label)}</p></button>`;
    return `<div class="entry grid-block event-block${size}" style="${style}">${s.events.map(e=>`<button class="grid-event" data-review="${escape(JSON.stringify([e.calendarId,e.id]))}" aria-label="Review ${escape(e.title)}: ${escape(label)}" ${busy||saving?'disabled':''}><h3>${escape(e.title)}</h3><p class="grid-calendar">${escape(e.categoryName||e.calendarName)}${s.events.length>1?' · Overlap counted once':''}${!writable().some(c=>c.id===e.calendarId)?' · Read only':''}</p><p class="grid-duration">${escape(label)}</p></button>`).join('')}</div>`;
  }).join('');
  return lines.join('')+`<div class="grid-canvas">${blocks}</div>`;
}
function render(){
  const now=Date.now();
  $('date').textContent=new Intl.DateTimeFormat('en-GB',{timeZone:tz,weekday:'long',day:'numeric',month:'long'}).format(now);
  $('zone').textContent=tz.replaceAll('_',' ');
  $('welcome').hidden=!!account;$('day').hidden=!account;$('settings').hidden=false;
  $('timeline').classList.toggle('twelve-hour',timeFormat==='12');$('now').classList.toggle('twelve-hour',timeFormat==='12');
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
  $('timeline').style.height=(data.elapsed/60000*pixelsPerMinute)+'px';
  $('timeline').innerHTML=ledgerGrid(data,bounds);
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
    if(!ids.length)throw new Error('Choose at least one calendar in Settings.');
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
  const dateTime=ms=>formatTime(ms,tz,timeFormat,{day:'numeric',month:'short'});
  $('delete-caption').textContent=event.calendarName+' · '+(event.allDay?'All day · '+event.startDate:dateTime(event.start)+' – '+dateTime(event.end));
  $('delete-recurring').hidden=!event.recurring;$('delete-guests').hidden=!event.hasGuests;
  const choices=[...categories];if(event.categoryId&&!choices.some(c=>c.id===event.categoryId))choices.push({id:event.categoryId,name:event.categoryName||'Saved category'});
  $('event-category').innerHTML='<option value="">Uncategorized</option>'+choices.map(c=>`<option value="${escape(c.id)}">${escape(c.name)}</option>`).join('');$('event-category').value=event.categoryId||'';
  $('event-category-section').hidden=!writable().some(c=>c.id===event.calendarId);
  $('category-preview-error').textContent='';
}
function openDelete(reference,review=false){
  if(!ready||busy||saving||pending||pendingDelete||!valid())return;
  let ids;try{ids=JSON.parse(reference);}catch{return;}
  const event=events.find(e=>e.calendarId===ids[0]&&e.id===ids[1]);
  if(!event||(!review&&!writable().some(c=>c.id===event.calendarId)))return;
  const canDelete=writable().some(c=>c.id===event.calendarId);
  $('delete-heading').textContent=review?'Event details':'Delete this event?';
  $('delete-confirm').hidden=!canDelete;
  $('delete-explanation').textContent=canDelete?'Delete this event from Google Calendar if you didn’t do it. Any time left uncovered will become a gap to fill in.':'This calendar is read only. This event can’t be deleted here.';
  $('delete-cancel').textContent=review?'Close':'Keep event';
  showDeleteEvent(event);$('delete-error').textContent='';$('delete-check').hidden=true;lockDelete(false);$('delete-dialog').showModal();
}
function lockDelete(locked){
  $('delete-confirm').disabled=locked||!!pendingDelete;
  $('delete-confirm').textContent=locked?'Deleting…':'Delete from Google Calendar';
  $('delete-check').disabled=locked;$('delete-cancel').disabled=locked;
  $('delete-dialog').querySelector('[data-close]').disabled=locked;
  $('preview-category').disabled=locked;$('event-category').disabled=locked;
}
function previewCategoryPlans(plans,meta){
  categoryPlans=plans;categoryMeta=meta;
  $('category-review-heading').textContent=meta.rename?'Preview category rename':'Preview category change';
  $('category-review-summary').textContent=`${plans.length} event${plans.length===1?'':'s'} will change. Titles, times, guests, and existing notes are preserved.`;
  $('category-review-list').innerHTML=plans.map(p=>`<details class="change-preview" ${plans.length===1?'open':''}><summary>${escape(p.title)}</summary><p class="form-note">${escape(p.calendarName||p.calendarId)} · ${escape(p.when.length>10?formatTime(Date.parse(p.when),tz,timeFormat,{day:'numeric',month:'short'}):p.when)}</p><h3>Current description</h3><pre>${escape(p.before.description||'(empty)')}</pre><h3>New description</h3><pre>${escape(p.after.description||'(empty)')}</pre></details>`).join('');
  $('category-apply').textContent=plans.length?`Confirm ${plans.length} event update${plans.length===1?'':'s'}`:'Save category name';
  $('category-review-error').textContent='';$('category-review-dialog').showModal();
}
async function previewEventCategory(){
  if(!deletingEvent||busy||saving||!valid())return;
  const target=deletingEvent,choice=$('event-category').value;
  const category=choice?categories.find(c=>c.id===choice)||{id:target.categoryId,name:target.categoryName}:null;
  busy=true;render();
  try{
    if(journal().unresolved())throw new Error('Check the interrupted category change in Settings first.');
    const raw=await calendarRequest(token,eventPath(target.calendarId,target.id)),plan=categoryPlan(raw,target.calendarId,category);plan.calendarName=target.calendarName;
    if(sameState(plan.before,plan.after))throw new Error('This event already has that category.');
    previewCategoryPlans([plan],{});
  }catch(e){$('category-preview-error').textContent=e.message;}finally{busy=false;render();}
}
function openRename(id){
  if(busy||saving)return;const category=categories.find(c=>c.id===id);if(!category)return;
  renameCategoryId=id;$('rename-name').value=category.name;$('rename-error').textContent='';$('rename-dialog').showModal();
}
async function previewRename(e){
  e.preventDefault();if(busy||saving||!valid())return;const category=categories.find(c=>c.id===renameCategoryId);if(!category)return;
  busy=true;render();
  try{
    const name=categoryName($('rename-name').value);
    if(categories.some(c=>c.id!==category.id&&c.name.toLowerCase()===name.toLowerCase()))throw new Error('Choose a unique category name.');
    if(journal().unresolved())throw new Error('Check the interrupted category change in Settings first.');
    const now=Date.now(),plans=await renamePlans(token,calendars,category,name,now,todayBounds(now,tz).date);
    previewCategoryPlans(plans,{rename:{id:category.id,from:category.name,to:name}});
  }catch(err){$('rename-error').textContent=err.message;}finally{busy=false;render();}
}
async function applyCategoryPlans(){
  if(saving||busy||pending||pendingDelete||!valid())return;
  saving=true;$('category-apply').disabled=true;render();
  try{
    if(categoryPlans.length&&!writeGranted)await authorization(READ_SCOPES+' '+WRITE_SCOPE);
    await confirmAccount();
    if(categoryPlans.some(p=>!writable().some(c=>c.id===p.calendarId)))throw new Error('A calendar is no longer writable. No changes were made.');
    const result=await journal().apply(token,categoryPlans,categoryMeta);
    if(categoryMeta.rename){const rename=categoryMeta.rename;categories=categories.map(c=>c.id===rename.id?{...c,name:rename.to}:c);persistCategories();}
    $('category-review-dialog').close();$('rename-dialog').close();$('delete-dialog').close();await sync();
    message(`Saved ${result.changed} category update${result.changed===1?'':'s'} to Google Calendar. Undo is available in Settings.`);
  }catch(e){$('category-review-error').textContent=e.message;}finally{saving=false;$('category-apply').disabled=false;render();}
}
async function categoryHistoryAction(undo){
  if(busy||saving||!account)return;saving=true;render();
  try{
    if(!valid()||(undo&&!writeGranted))await authorization(READ_SCOPES+(undo?' '+WRITE_SCOPE:''));
    await confirmAccount();
    if(undo){const batch=await journal().undo(token);if(batch.meta.rename){const rename=batch.meta.rename;categories=categories.map(c=>c.id===rename.id?{...c,name:rename.from}:c);persistCategories();}$('category-status').textContent='Restored the previous category notes.';}
    else{const count=await journal().recover(token);$('category-status').textContent=`Checked ${count} interrupted update${count===1?'':'s'}.`;}
    await sync();
  }catch(e){$('category-status').textContent=e.message;}finally{saving=false;render();}
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
$('preview-category').onclick=previewEventCategory;$('category-apply').onclick=applyCategoryPlans;
$('rename-form').onsubmit=previewRename;$('undo-category').onclick=()=>categoryHistoryAction(true);$('check-category').onclick=()=>categoryHistoryAction(false);
$('category-form').onsubmit=e=>{
  e.preventDefault();if(busy||saving||!account)return;
  try{const name=categoryName($('category-name').value);if(categories.some(c=>c.name.toLowerCase()===name.toLowerCase()))throw new Error('That category already exists.');categories.push({id:crypto.randomUUID(),name});persistCategories();$('category-name').value='';$('category-status').textContent='Category added. Choose it when reviewing an event.';renderSettings();}catch(err){$('category-status').textContent=err.message;}
};
$('download-backup').onclick=()=>{
  if(!account)return;
  try{const backup=JSON.stringify(journal().read(),null,2),url=URL.createObjectURL(new Blob([backup],{type:'application/json'})),link=document.createElement('a');link.href=url;link.download='time-ledger-category-backup.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),10000);}catch(e){$('category-status').textContent=e.message;}
};
$('connect').onclick=connect;$('reconnect').onclick=async()=>{await connect();};
$('refresh').onclick=()=>valid()?sync():connect();
$('settings').onclick=()=>{renderSettings();$('settings-dialog').showModal();};
$('time-format').onchange=()=>{
  timeFormat=$('time-format').value==='12'?'12':'24';
  try{localStorage.setItem(timeFormatKey,timeFormat);}catch{message('The time format changed, but could not be saved on this device.',true);}
  render();
  if($('gap-dialog').open&&gap)$('gap-caption').textContent=`${fmt(gap.start)}–${fmt(gap.end)} · ${duration(gap.end-gap.start)} unrecorded`;
  if($('delete-dialog').open&&deletingEvent)showDeleteEvent(deletingEvent);
};
$('disconnect').onclick=()=>{
  const old=token;token=null;expires=0;account=null;writeGranted=false;calendars=[];events=[];selected=[];lastRead=null;ready=false;pending=null;retryDraft=null;pendingDelete=null;deletingEvent=null;
  $('settings-dialog').close();message('Disconnected. Loaded Calendar data has been cleared.');render();
  if(old&&window.google?.accounts?.oauth2)google.accounts.oauth2.revoke(old,()=>{});
};
$('calendar-list').onchange=async e=>{
  const id=e.target.dataset.calendar;if(!id||busy||saving)return;
  selected=e.target.checked?[...new Set([...selected,id])]:selected.filter(x=>x!==id);savePrefs();await sync();
};
$('fill-first').onclick=()=>{const bounds=todayBounds(lastRead,tz),data=accountDay(events,bounds);openGap(data.segments.findIndex(s=>s.kind==='gap'));};
document.addEventListener('click',e=>{
  const close=e.target.closest('[data-close]');if(close){if(saving)return;close.closest('dialog').close();return;}
  const remove=e.target.closest('[data-delete]');if(remove){openDelete(remove.dataset.delete);return;}
  const review=e.target.closest('[data-review]');if(review){openDelete(review.dataset.review,true);return;}
  const rename=e.target.closest('[data-rename-category]');if(rename){openRename(rename.dataset.renameCategory);return;}
  const button=e.target.closest('[data-gap]');if(button){retryDraft=null;openGap(Number(button.dataset.gap));}
});
$('gap-dialog').addEventListener('cancel',e=>{if(saving)e.preventDefault();});
$('gap-dialog').addEventListener('close',()=>{if(!pending)retryDraft=null;});
$('delete-dialog').addEventListener('cancel',e=>{if(saving)e.preventDefault();});
$('delete-dialog').addEventListener('close',()=>{if(!pendingDelete)deletingEvent=null;});
['category-review-dialog','rename-dialog'].forEach(id=>$(id).addEventListener('cancel',e=>{if(saving)e.preventDefault();}));
document.addEventListener('visibilitychange',()=>{if(!document.hidden){render();if(valid()&&!busy&&!saving&&!$('gap-dialog').open&&!$('delete-dialog').open)sync();}});
setInterval(()=>{if(!document.hidden&&!busy&&!saving&&!$('gap-dialog').open&&!$('delete-dialog').open){if(valid())sync();else render();}},60000);
if('serviceWorker' in navigator)navigator.serviceWorker.register('/sw.js',{scope:'/'}).catch(()=>{});
render();
