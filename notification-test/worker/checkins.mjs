import {INTERVAL,localStamp,dayBounds,formatTime,slotEnd,scheduledSlot,slotsForDay,validDate} from '../checkins/core.mjs';
const checkinHeaders={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const checkinJson=(data,status=200)=>Response.json(data,{status,headers:checkinHeaders});
class CheckinError extends Error{constructor(message,status=400){super(message);this.status=status;}}
const query=(db,sql,...params)=>db.prepare(sql).bind(...params);
function timezone(value){try{new Intl.DateTimeFormat('en',{timeZone:value}).format();return value;}catch{throw new CheckinError('Choose a valid timezone.');}}
function categoryLabel(value){const name=typeof value==='string'?value.trim():'';if(!name||name.length>60)throw new CheckinError('Enter a category name of 1–60 characters.');return name;}
async function initializeUser(db,user,tz){
 await query(db,'INSERT OR IGNORE INTO checkin_settings(user_id,timezone) VALUES(?,?)',user,timezone(tz||'Europe/Berlin')).run();
 // Seed only on first use; persisted category IDs keep edits reflected on every entry.
 const count=await query(db,'SELECT COUNT(*) AS count FROM checkin_categories WHERE user_id=?',user).first();
 if(!count.count)await db.batch([['classes','Preparing classes','#315eec'],['work','Other work','#8c79d2'],['personal','Personal','#42a995'],['rest','Rest','#d3a052']].map(c=>query(db,'INSERT OR IGNORE INTO checkin_categories(user_id,id,name,normalized_name,color) VALUES(?,?,?,?,?)',user,...[c[0],c[1],c[1].toLowerCase(),c[2]])));
 return query(db,'SELECT * FROM checkin_settings WHERE user_id=?',user).first();
}
async function bodyJson(request){const text=await request.text();if(text.length>16384)throw new CheckinError('Request is too large.',413);try{return JSON.parse(text);}catch{throw new CheckinError('Expected a JSON request.');}}
function requireVersion(value){if(!Number.isInteger(value)||value<0)throw new CheckinError('Refresh this entry before saving.');return value;}
async function ownedDevice(db,user,id){const device=await query(db,'SELECT * FROM checkin_devices WHERE id=? AND user_id=?',id,user).first();if(!device)throw new CheckinError('This notification device was not found.',404);return device;}
function promptFor(device,settings,now){
 const end=device?.last_push_slot||slotEnd(now),test=device?.last_push_kind==='test';
 return {title:test?'Check-in test':'What were you doing?',body:`${formatTime(end-INTERVAL,settings.timezone,settings.time_format)}–${formatTime(end,settings.timezone,settings.time_format)} · Tap to record the last 15 minutes.`,url:'/?slot='+end,slot:end,test};
}
export async function handleCheckins(request,env,services){
 const url=new URL(request.url);if(!url.pathname.startsWith('/api/checkins'))return null;
 try{
  if(!env.DB)throw new CheckinError('The log database is not ready yet.',503);
  if(url.pathname==='/api/checkins/tick'){
   if(request.method!=='POST')throw new CheckinError('Use POST.',405);
   const supplied=request.headers.get('X-Checkin-Scheduler-Token');
   if(!env.CHECKIN_SCHEDULER_TOKEN||supplied!==env.CHECKIN_SCHEDULER_TOKEN)throw new CheckinError('Scheduler authorization required.',403);
   return checkinJson(await tickCheckins(env,services));
  }
  const user=request.headers.get('oai-authenticated-user-id');if(!user)throw new CheckinError('Sign in to your private app to load your log.',401);
  if(request.method!=='GET'){
   if(request.headers.get('Origin')!==url.origin)throw new CheckinError('Open the app at its own address before saving.',403);
   if(!request.headers.get('Content-Type')?.startsWith('application/json'))throw new CheckinError('Expected JSON.',415);
  }
  const db=env.DB,now=Date.now(),settings=await initializeUser(db,user,url.searchParams.get('tz'));
  if(request.method==='GET'&&url.pathname==='/api/checkins'){
   const date=url.searchParams.get('date')||localStamp(now,settings.timezone).slice(0,10),bounds=dayBounds(date,settings.timezone);
   if(date>localStamp(now,settings.timezone).slice(0,10))throw new CheckinError('Choose today or an earlier date.');
   const [categories,entries,devices,heartbeat]=await Promise.all([
    query(db,'SELECT id,name,color FROM checkin_categories WHERE user_id=? ORDER BY name',user).all(),
    query(db,'SELECT * FROM checkin_entries WHERE user_id=? AND start_ms>=? AND start_ms<? ORDER BY end_ms DESC',user,bounds.start,bounds.end).all(),
    query(db,'SELECT id,active,last_error FROM checkin_devices WHERE user_id=?',user).all(),query(db,"SELECT value FROM checkin_runtime WHERE key='last_tick'").first()
   ]);
   return checkinJson({userId:user,date,settings,categories:categories.results,entries:entries.results,slots:slotsForDay(date,settings.timezone,now),devices:devices.results,publicKey:env.VAPID_PUBLIC_KEY||null,scheduler:{configured:env.CHECKIN_SCHEDULER_ENABLED==='1',lastTick:heartbeat?Number(heartbeat.value):null},now});
  }
  if(request.method==='GET'&&url.pathname==='/api/checkins/prompt'){
   const id=url.searchParams.get('device'),device=id?await ownedDevice(db,user,id):null;
   return checkinJson(promptFor(device,settings,now));
  }
  const data=await bodyJson(request);
  if(request.method==='POST'&&url.pathname==='/api/checkins/entry'){
   const end=data.end,version=requireVersion(data.version),activity=typeof data.activity==='string'?data.activity.trim():'';
   if(!Number.isSafeInteger(end)||end%INTERVAL!==0||end>now||end<now-366*86400000)throw new CheckinError('Choose a completed 15-minute period within the past year.');
   if(!activity||activity.length>500)throw new CheckinError('Describe what you were doing in 1–500 characters.');
   const categoryId=data.categoryId||null;
   if(categoryId&&!await query(db,'SELECT id FROM checkin_categories WHERE user_id=? AND id=?',user,categoryId).first())throw new CheckinError('Choose one of your categories.');
   const current=await query(db,'SELECT * FROM checkin_entries WHERE user_id=? AND end_ms=?',user,end).first();
   if(current&&current.activity===activity&&current.category_id===categoryId)return checkinJson({entry:current,saved:true});
   if(current&&current.version!==version||!current&&version!==0)throw new CheckinError('This entry changed. Refresh and review it before saving.',409);
   if(!current){
    const result=await query(db,'INSERT OR IGNORE INTO checkin_entries(user_id,end_ms,start_ms,activity,category_id,answered_at,updated_at) VALUES(?,?,?,?,?,?,?)',user,end,end-INTERVAL,activity,categoryId,now,now).run();
    if(!result.meta.changes)throw new CheckinError('Another answer was saved for this period. Refresh first.',409);
   }else{
    const result=await query(db,'UPDATE checkin_entries SET activity=?,category_id=?,updated_at=?,version=version+1 WHERE user_id=? AND end_ms=? AND version=?',activity,categoryId,now,user,end,version).run();
    if(!result.meta.changes)throw new CheckinError('This entry changed. Refresh first.',409);
   }
   return checkinJson({saved:true,entry:await query(db,'SELECT * FROM checkin_entries WHERE user_id=? AND end_ms=?',user,end).first()});
  }
  if(request.method==='POST'&&url.pathname==='/api/checkins/category'){
   const name=categoryLabel(data.name),id=data.id||crypto.randomUUID(),normalized=name.toLowerCase();
   const collision=await query(db,'SELECT id FROM checkin_categories WHERE user_id=? AND normalized_name=? AND id<>?',user,normalized,id).first();if(collision)throw new CheckinError('That category name already exists.');
   if(data.id){const result=await query(db,'UPDATE checkin_categories SET name=?,normalized_name=? WHERE user_id=? AND id=?',name,normalized,user,id).run();if(!result.meta.changes)throw new CheckinError('That category was not found.',404);}
   else await query(db,'INSERT INTO checkin_categories(user_id,id,name,normalized_name,color) VALUES(?,?,?,?,?)',user,id,name,normalized,'#315eec').run();
   return checkinJson({saved:true,id});
  }
  if(request.method==='POST'&&url.pathname==='/api/checkins/settings'){
   const start=data.startMinute,end=data.endMinute,tz=timezone(data.timezone);
   if(!Number.isInteger(start)||!Number.isInteger(end)||start<0||end>1440||end<=start||start%15||end%15)throw new CheckinError('Choose a start and end on 15-minute boundaries, within one day.');
   if(!['12','24'].includes(data.timeFormat)||typeof data.enabled!=='boolean')throw new CheckinError('Choose valid notification settings.');
   const version=requireVersion(data.version),result=await query(db,'UPDATE checkin_settings SET timezone=?,start_minute=?,end_minute=?,enabled=?,time_format=?,version=version+1 WHERE user_id=? AND version=?',tz,start,end,data.enabled?1:0,data.timeFormat,user,version).run();
   if(!result.meta.changes)throw new CheckinError('Settings changed on another device. Refresh first.',409);
   return checkinJson({saved:true});
  }
  if(request.method==='POST'&&url.pathname==='/api/checkins/device'){
   const endpoint=services.validateEndpoint(data.endpoint).href,id=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(endpoint))),b=>b.toString(16).padStart(2,'0')).join('');
   const existing=await query(db,'SELECT user_id FROM checkin_devices WHERE id=?',id).first();if(existing&&existing.user_id!==user)throw new CheckinError('This device is registered to another account. Reset its push subscription first.',409);
   await query(db,'INSERT INTO checkin_devices(id,user_id,endpoint,registered_at) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET active=1,registered_at=excluded.registered_at,last_error=NULL',id,user,endpoint,now).run();return checkinJson({id,saved:true});
  }
  if(request.method==='POST'&&url.pathname==='/api/checkins/device-disable'){
   await ownedDevice(db,user,data.id);await query(db,'UPDATE checkin_devices SET active=0 WHERE id=? AND user_id=?',data.id,user).run();return checkinJson({saved:true});
  }
  if(request.method==='POST'&&url.pathname==='/api/checkins/push-test'){
   const device=await ownedDevice(db,user,data.id);if(!device.active)throw new CheckinError('Enable notifications on this device first.');
   await query(db,"UPDATE checkin_devices SET last_push_slot=?,last_push_kind='test' WHERE id=? AND user_id=?",slotEnd(now),device.id,user).run();
   await services.sendPush(device.endpoint,env);return checkinJson({accepted:true});
  }
  throw new CheckinError('Not found.',404);
 }catch(e){return checkinJson({error:e instanceof CheckinError?e.message:'The request could not be completed. Your draft is still on screen.'},e instanceof CheckinError?e.status:502);}
}
export async function tickCheckins(env,services){
 const db=env.DB;if(!db)throw new CheckinError('The log database is not ready.',503);
 const now=Date.now();await query(db,"INSERT INTO checkin_runtime(key,value) VALUES('last_tick',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",String(now)).run();
 if(env.CHECKIN_SCHEDULER_ENABLED!=='1')return {configured:false,checked:0,accepted:0};
 const users=await db.prepare('SELECT * FROM checkin_settings WHERE enabled=1').all();let checked=0,accepted=0;
 for(const settings of users.results){
  const end=scheduledSlot(now,settings);if(!end)continue;
  if(await query(db,'SELECT end_ms FROM checkin_entries WHERE user_id=? AND end_ms=?',settings.user_id,end).first())continue;
  const devices=await query(db,'SELECT * FROM checkin_devices WHERE user_id=? AND active=1',settings.user_id).all();
  for(const device of devices.results){
   const claimed=await query(db,'INSERT OR IGNORE INTO checkin_reminders(device_id,end_ms,attempted_at) VALUES(?,?,?)',device.id,end,now).run();if(!claimed.meta.changes)continue;checked++;
   await query(db,"UPDATE checkin_devices SET last_push_slot=?,last_push_kind='reminder' WHERE id=?",end,device.id).run();
   try{await services.sendPush(device.endpoint,env);accepted++;await query(db,"UPDATE checkin_reminders SET status='accepted',accepted_at=? WHERE device_id=? AND end_ms=?",Date.now(),device.id,end).run();await query(db,'UPDATE checkin_devices SET last_error=NULL WHERE id=?',device.id).run();}
   catch(e){const expired=/expired/.test(e.message);await db.batch([query(db,"UPDATE checkin_reminders SET status='failed' WHERE device_id=? AND end_ms=?",device.id,end),query(db,'UPDATE checkin_devices SET last_error=?,active=? WHERE id=?',expired?'Subscription expired. Enable notifications again.':'The last push could not be confirmed.',expired?0:1,device.id)]);}
  }
 }
 return {configured:true,checked,accepted};
}
