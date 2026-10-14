import {INTERVAL,localStamp,formatTime,scheduleTime,breakdown,minutesLabel} from './core.mjs';
const $=id=>document.getElementById(id),escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const phoneZone=Intl.DateTimeFormat().resolvedOptions().timeZone||'Europe/Berlin';
let data=null,busy=false,saving=false,filter=false,view='log',selectedEnd=null,editing=null,renaming=null,reg=null,subscription=null,deviceId=null;
const installed=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
const ios=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
const note=(text,error=false)=>{$('message').textContent=text;$('message').hidden=!text;$('message').classList.toggle('error',error);};
const time=ms=>formatTime(ms,data?.settings.timezone||phoneZone,data?.settings.time_format||'12');
const interval=end=>time(end-INTERVAL)+'–'+time(end);
const options=()=>'<option value="">Categorize later</option>'+(data?.categories||[]).map(c=>`<option value="${escape(c.id)}">${escape(c.name)}</option>`).join('');
const category=id=>data?.categories.find(c=>c.id===id);
const clockValue=min=>`${String(Math.floor(min/60)%24).padStart(2,'0')}:${String(min%60).padStart(2,'0')}`;
async function api(path,body){
 let response;try{response=await fetch(path,{credentials:'same-origin',cache:'no-store',...(body!==undefined?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{})});}catch{throw new Error('Could not reach the server. Your answer is still here; try again when connected.');}
 let result;try{result=await response.json();}catch{throw new Error('Sign in to this app in Safari, then reopen it from your Home Screen.');}
 if(!response.ok){const error=new Error(result.error||'The request failed.');error.status=response.status;throw error;}return result;
}
function renderSettings(){
 if(!data)return;const s=data.settings;
 $('reminders-enabled').checked=!!s.enabled;$('start-time').value=clockValue(s.start_minute);$('end-time').value=clockValue(s.end_minute);$('time-format').value=s.time_format;
 $('schedule-caption').textContent=`First check-in ${scheduleTime(s.start_minute+15,s.time_format)}; last ${scheduleTime(s.end_minute,s.time_format)}. Missed prompts are okay.`;
 $('settings-zone').textContent=`Schedule timezone: ${s.timezone.replaceAll('_',' ')}. Saving settings uses this phone’s timezone (${phoneZone.replaceAll('_',' ')}).`;
 $('category-list').innerHTML=data.categories.map(c=>`<div class="category-row"><span>${escape(c.name)}</span><button class="text-button" data-rename="${escape(c.id)}" ${saving||busy?'disabled':''}>Rename</button></div>`).join('');
 $('save-settings').disabled=saving||busy;$('save-rename').disabled=saving||busy;
 $('enable-notifications').disabled=saving||busy||!reg||!data.publicKey||ios&&!installed();
 $('enable-notifications').textContent=subscription?'Notifications enabled':ios&&!installed()?'Install from Safari first':'Enable notifications';
 $('test-notification').disabled=saving||busy||!deviceId;$('reset-notifications').disabled=saving||busy||!deviceId;
 $('device-status').textContent=subscription?'Push subscription saved for this device.':('Notification' in window&&Notification.permission==='denied'?'Permission is blocked. Enable alerts in iPhone Settings → Notifications → Time Ledger.':'Enable notifications to receive check-ins with the app closed.');
 $('scheduler-status').textContent=!data.scheduler.configured?'Automatic reminders are waiting for scheduler setup. Logging and test notifications work now.':data.scheduler.lastTick&&Date.now()-data.scheduler.lastTick<20*60000?'The recurring scheduler is connected and has checked in recently.':'The scheduler has not checked in recently. Reminders may be delayed; your log still works.';
}
function render(){
 $('save-answer').disabled=busy||saving||!data||!selectedEnd;$('save-edit').disabled=busy||saving;$('refresh').disabled=busy||saving;
 if(!data)return;
 $('date').value=data.date;$('date').max=localStamp(data.now,data.settings.timezone).slice(0,10);$('zone').textContent=data.settings.timezone.replaceAll('_',' ');
 $('day-heading').textContent=data.date===localStamp(Date.now(),data.settings.timezone).slice(0,10)?'Today':'Your log';
 $('prompt-period').textContent=selectedEnd?interval(selectedEnd):'The first completed 15-minute period will appear here.';
 const saved=data.entries.find(e=>e.end_ms===selectedEnd);$('save-answer').textContent=saved?'Update check-in':'Save check-in';
 $('log-tab').classList.toggle('active',view==='log');$('breakdown-tab').classList.toggle('active',view==='breakdown');$('log-tab').setAttribute('aria-pressed',String(view==='log'));$('breakdown-tab').setAttribute('aria-pressed',String(view==='breakdown'));$('log-view').hidden=view!=='log';$('breakdown-view').hidden=view!=='breakdown';
 const uncategorized=data.entries.filter(e=>!e.category_id).length;$('uncategorized-filter').textContent=`To categorize${uncategorized?' · '+uncategorized:''}`;$('all-filter').classList.toggle('active',!filter);$('uncategorized-filter').classList.toggle('active',filter);
 const rows=filter?data.entries.filter(e=>!e.category_id):data.entries;
 $('entries').innerHTML=rows.length?rows.map(e=>`<button class="entry" data-edit="${e.end_ms}"><div class="entry-top"><span class="entry-time">${interval(e.end_ms)} · 15m</span><span class="tag${e.category_id?'':' uncategorized'}">${escape(category(e.category_id)?.name||'Categorize later')}</span></div><div class="entry-title">${escape(e.activity)}</div></button>`).join(''):`<div class="empty">${filter?'All your recorded entries have a category.':'No answers recorded yet. Save a quick check-in above to start.'}</div>`;
 const stats=breakdown(data.entries,data.categories);$('logged-total').textContent=minutesLabel(stats.logged);
 const bar=(name,mins,color)=>`<div class="breakdown-row"><div class="breakdown-top"><strong>${escape(name)}</strong><span class="breakdown-value">${minutesLabel(mins)} · ${(mins/1440*100).toFixed(1)}%</span></div><div class="bar"><span style="width:${Math.min(100,mins/1440*100)}%;background:${color}"></span></div></div>`;
 $('breakdown').innerHTML=stats.categories.map(c=>bar(c.name,c.minutes,/^#[0-9a-f]{6}$/i.test(c.color)?c.color:'#315eec')).join('')+bar('Uncategorized answers',stats.uncategorized,'#d3a052')+bar('Not logged yet',stats.unlogged,'#b5bdcb');
 const running=data.scheduler.configured&&data.scheduler.lastTick&&Date.now()-data.scheduler.lastTick<20*60000,ready=!!subscription&&running&&data.settings.enabled;$('reminder-dot').classList.toggle('ready',ready);
 $('reminder-status').textContent=!data.settings.enabled?'Reminders paused':!data.scheduler.configured?'Reminders waiting for scheduler setup':!running?'Waiting for the reminder scheduler':!subscription?'Enable notifications in Settings':'15-minute reminders · '+scheduleTime(data.settings.start_minute,data.settings.time_format)+'–'+scheduleTime(data.settings.end_minute,data.settings.time_format);
 renderSettings();
}
function populatePrompt(end){
 selectedEnd=end;const current=data.entries.find(e=>e.end_ms===end);$('activity').value=current?.activity||'';$('category').innerHTML=options();$('category').value=current?.category_id||'';
 $('period-selector').innerHTML=[...data.slots].reverse().map(s=>`<option value="${s}">${interval(s)}${data.entries.some(e=>e.end_ms===s)?' · recorded':''}</option>`).join('');$('period-selector').value=String(end||'');render();
}
async function load(date=null,keepDraft=false){
 if(busy)return;busy=true;render();const draft={activity:$('activity').value,category:$('category').value,end:selectedEnd};
 try{
  const next=await api('/api/checkins?tz='+encodeURIComponent(phoneZone)+(date?'&date='+date:''));data=next;
  const fromUrl=Number(new URLSearchParams(location.search).get('slot'));
  const end=keepDraft&&data.slots.includes(draft.end)?draft.end:data.slots.includes(fromUrl)?fromUrl:data.slots.at(-1)||null;
  populatePrompt(end);if(keepDraft&&end===draft.end){$('activity').value=draft.activity;$('category').value=draft.category;}
 }catch(e){note(e.message,true);}finally{busy=false;render();}
}
async function registerDevice(){
 if(!reg||!data?.publicKey)return;
 subscription=await reg.pushManager.getSubscription();if(!subscription)return;
 const saved=await api('/api/checkins/device',{endpoint:subscription.endpoint});deviceId=saved.id;
 const sw=reg.active||navigator.serviceWorker.controller;sw?.postMessage({type:'checkin-device',id:deviceId});
}
async function initialize(){
 $('install-hint').hidden=!ios||installed();await load();
 if('serviceWorker' in navigator){try{await navigator.serviceWorker.register('/sw.js',{scope:'/'});reg=await navigator.serviceWorker.ready;if('PushManager' in window)await registerDevice();}catch(e){note('Your log is ready, but notification setup needs another try: '+e.message,true);}}
 const slot=Number(new URLSearchParams(location.search).get('slot'));
 if(data&&Number.isSafeInteger(slot)&&slot>0&&!data.slots.includes(slot)){const date=localStamp(slot-INTERVAL,data.settings.timezone).slice(0,10);if(date<=localStamp(Date.now(),data.settings.timezone).slice(0,10))await load(date);}
 render();
}
$('answer-form').onsubmit=async e=>{
 e.preventDefault();if(saving||busy||!selectedEnd)return;saving=true;render();
 try{const current=data.entries.find(e=>e.end_ms===selectedEnd);await api('/api/checkins/entry',{end:selectedEnd,activity:$('activity').value,categoryId:$('category').value||null,version:current?.version||0});await load(data.date);note('Check-in saved. You can change its category anytime.');}catch(err){note(err.message,true);}finally{saving=false;render();}
};
$('choose-period').onclick=()=>{$('period-selector').hidden=!$('period-selector').hidden;};$('period-selector').onchange=()=>populatePrompt(Number($('period-selector').value));
$('date').onchange=()=>load($('date').value);$('refresh').onclick=()=>load(data?.date,true);
$('log-tab').onclick=()=>{view='log';render();};$('breakdown-tab').onclick=()=>{view='breakdown';render();};$('all-filter').onclick=()=>{filter=false;render();};$('uncategorized-filter').onclick=()=>{filter=true;render();};
$('settings-button').onclick=()=>{renderSettings();$('settings-dialog').showModal();};
$('edit-form').onsubmit=async e=>{
 e.preventDefault();if(saving||busy||!editing)return;saving=true;render();$('edit-error').textContent='';
 try{await api('/api/checkins/entry',{end:editing.end_ms,activity:$('edit-activity').value,categoryId:$('edit-category').value||null,version:editing.version});$('edit-dialog').close();await load(data.date,true);note('Entry updated.');}catch(err){$('edit-error').textContent=err.message;}finally{saving=false;render();}
};
$('settings-form').onsubmit=async e=>{
 e.preventDefault();if(saving||busy||!data)return;
 const minute=s=>Number(s.slice(0,2))*60+Number(s.slice(3,5));
 const payload={startMinute:minute($('start-time').value),endMinute:minute($('end-time').value),enabled:$('reminders-enabled').checked,timeFormat:$('time-format').value,timezone:phoneZone,version:data.settings.version};saving=true;render();$('settings-error').textContent='';
 try{await api('/api/checkins/settings',payload);await load(data.date,true);note('Reminder hours saved.');}catch(err){$('settings-error').textContent=err.message;}finally{saving=false;render();}
};
$('category-form').onsubmit=async e=>{e.preventDefault();if(saving||busy)return;saving=true;render();try{await api('/api/checkins/category',{name:$('new-category').value});$('new-category').value='';await load(data.date,true);$('category-error').textContent='';}catch(err){$('category-error').textContent=err.message;}finally{saving=false;render();}};
$('rename-form').onsubmit=async e=>{e.preventDefault();if(saving||busy||!renaming)return;saving=true;render();try{await api('/api/checkins/category',{id:renaming,name:$('rename-name').value});$('rename-dialog').close();await load(data.date,true);note('Category renamed on all your entries.');}catch(err){$('rename-error').textContent=err.message;}finally{saving=false;render();}};
$('enable-notifications').onclick=async()=>{
 if(!reg||!data||saving||busy)return;saving=true;render();
 try{
  const permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('Allow notifications in your phone’s notification settings.');
  const bytes=Uint8Array.from(atob(data.publicKey.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(data.publicKey.length/4)*4,'=')),c=>c.charCodeAt(0));
  subscription=await reg.pushManager.getSubscription()||await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes});await registerDevice();note('Notifications enabled on this device. Try a test notification.');
 }catch(e){note(e.message,true);}finally{saving=false;render();}
};
$('test-notification').onclick=async()=>{if(!deviceId||saving||busy)return;saving=true;render();try{await api('/api/checkins/push-test',{id:deviceId});note('The push service accepted the test. Check your phone or Watch.');}catch(e){note(e.message,true);}finally{saving=false;render();}};
$('reset-notifications').onclick=async()=>{if(!deviceId||saving||busy)return;saving=true;render();try{await api('/api/checkins/device-disable',{id:deviceId});await subscription?.unsubscribe();subscription=null;deviceId=null;note('Subscription reset. Enable notifications again.');}catch(e){note(e.message,true);}finally{saving=false;render();}};
$('export-log').onclick=()=>{if(!data)return;const text=JSON.stringify({date:data.date,timezone:data.settings.timezone,entries:data.entries.map(e=>({...e,category:category(e.category_id)?.name||null}))},null,2),url=URL.createObjectURL(new Blob([text],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='time-ledger-'+data.date+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);};
document.addEventListener('click',e=>{
 const close=e.target.closest('[data-close]');if(close){if(!saving)close.closest('dialog').close();return;}
 const edit=e.target.closest('[data-edit]');if(edit&&!saving&&!busy){editing=data.entries.find(x=>x.end_ms===Number(edit.dataset.edit));if(!editing)return;$('edit-period').textContent=interval(editing.end_ms)+' · 15m';$('edit-activity').value=editing.activity;$('edit-category').innerHTML=options();$('edit-category').value=editing.category_id||'';$('edit-error').textContent='';$('edit-dialog').showModal();return;}
 const rename=e.target.closest('[data-rename]');if(rename&&!saving&&!busy){renaming=rename.dataset.rename;$('rename-name').value=category(renaming)?.name||'';$('rename-error').textContent='';$('rename-dialog').showModal();}
});
document.querySelectorAll('dialog').forEach(d=>d.addEventListener('cancel',e=>{if(saving)e.preventDefault();}));
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&!saving&&!busy&&!document.querySelector('dialog[open]'))load(data?.date,true);});
setInterval(()=>{if(document.hidden||saving||busy||!data||document.querySelector('dialog[open]'))return;const current=data.entries.find(e=>e.end_ms===selectedEnd),hasDraft=$('activity').value.trim()&&(!current||$('activity').value!==current.activity||($('category').value||null)!==current.category_id);load(data.date,!!hasDraft);},60000);
initialize();
