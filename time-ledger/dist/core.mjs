export const UNCLASSIFIED = {id:'uncategorized',name:'Uncategorized',color:'#a0a9b9'};
export const CONFLICT = {id:'overlap',name:'Overlapping time',color:'#c49556'};
export const DEFAULT_CATEGORIES = [
  {id:'product',name:'Product',color:'#2f60ed',important:true,keywords:['product','build','design','engineering','development','coding']},
  {id:'clients',name:'Clients',color:'#42a995',important:true,keywords:['client','outreach','proposal','sales','customer']},
  {id:'team',name:'Team',color:'#8c79d2',important:false,keywords:['team','standup','stand-up','1:1','all hands']},
  {id:'admin',name:'Admin',color:'#d3a052',important:false,keywords:['admin','invoice','finance','expenses','planning']},
  {id:'learning',name:'Learning',color:'#d17fa1',important:false,keywords:['learning','course','study','reading','research']}
];
export function dateParts(ms,tz){
  const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(ms).map(p=>[p.type,p.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}`;
}
// Reject nonexistent DST times; choose the earlier occurrence of repeated times.
export function localToMs(value,tz){
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value))throw new Error('Choose a valid start time.');
  const full=value.length===16?value+':00':value, guess=Date.parse(full+'Z');
  if(!Number.isFinite(guess))throw new Error('Choose a valid start time.');
  const candidates=new Set();
  for(const delta of [-36,-12,0,12,36]){
    const probe=guess+delta*3600000;
    const offset=Date.parse(dateParts(probe,tz)+'Z')-probe;
    const candidate=guess-offset;
    if(dateParts(candidate,tz)===full)candidates.add(candidate);
  }
  if(!candidates.size)throw new Error('That local time does not exist because of a clock change. Choose another time.');
  return Math.min(...candidates);
}
function shiftDate(date,days){const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+days);return d.toISOString().slice(0,10);}
export function periodBounds(now,tz,period='today'){
  const today=dateParts(now,tz).slice(0,10);
  const weekday=new Date(today+'T12:00:00Z').getUTCDay();
  const startDate=period==='week'?shiftDate(today,-((weekday+6)%7)):today;
  const endDate=shiftDate(startDate,period==='week'?7:1);
  return {start:localToMs(startDate+'T00:00',tz),end:localToMs(endDate+'T00:00',tz),now,startDate,endDate};
}
export function normalizeEvent(raw,calendar){
  if(raw.status==='cancelled'||raw.attendees?.some(a=>a.self&&a.responseStatus==='declined'))return null;
  if(['workingLocation','birthday','outOfOffice'].includes(raw.eventType))return null;
  if(!raw.start?.dateTime||!raw.end?.dateTime)return null;
  const start=Date.parse(raw.start.dateTime),end=Date.parse(raw.end.dateTime);
  if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return null;
  const uid=raw.iCalUID||`${calendar.id}:${raw.id}`;
  return {id:raw.id,key:JSON.stringify([uid,start]),uid,seriesKey:raw.recurringEventId?JSON.stringify([calendar.id,raw.recurringEventId]):null,start,end,title:raw.summary||'(Untitled event)',description:raw.description||'',attendees:raw.attendees||[],calendarId:calendar.id,calendarName:calendar.summary||calendar.id,url:raw.htmlLink||null,tag:raw.extendedProperties?.private?.timeLedgerCategory||null,updated:Date.parse(raw.updated||'')||0};
}
const phraseMatches=(text,word)=>{
  const escaped=word.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  return new RegExp(`(?:^|[^\\p{L}\\p{N}])${escaped}(?:$|[^\\p{L}\\p{N}])`,'iu').test(text);
};
export function classify(event,categories,assignments={},series={}){
  const valid=new Set([...categories.map(c=>c.id),UNCLASSIFIED.id]);
  if(valid.has(assignments[event.key]))return {category:assignments[event.key],reason:'Your choice'};
  if(event.seriesKey&&valid.has(series[event.seriesKey]))return {category:series[event.seriesKey],reason:'Saved series rule'};
  if(valid.has(event.tag))return {category:event.tag,reason:'Chosen when created'};
  const label=event.title.match(/^\[([^\]]+)\]/)?.[1];
  const labeled=label&&categories.filter(c=>c.name.toLowerCase()===label.toLowerCase());
  if(labeled?.length===1)return {category:labeled[0].id,reason:'Event label'};
  const text=event.title+' '+event.description;
  const matches=categories.filter(c=>c.keywords.some(k=>k&&phraseMatches(text,k)));
  return matches.length===1?{category:matches[0].id,reason:'Suggested from matching words'}:{category:UNCLASSIFIED.id,reason:matches.length>1?'Multiple categories match':'Choose a category'};
}
export function deduplicate(events){
  const unique=new Map();
  for(const event of events){const prior=unique.get(event.key);if(!prior||event.updated>prior.updated)unique.set(event.key,event);}
  return [...unique.values()];
}
export function allocate(events,bounds,categories,assignments={},series={}){
  const now=Math.min(bounds.now,bounds.end);
  const entries=deduplicate(events).map(e=>({...e,...classify(e,categories,assignments,series)}));
  const elapsed=entries.filter(e=>e.start<now&&e.end>bounds.start);
  const upcoming=entries.filter(e=>e.end>Math.max(bounds.now,bounds.start)&&e.start<bounds.end);
  function sweep(list,left,right){
    const cuts=new Map();
    const add=(at,type,e)=>{if(!cuts.has(at))cuts.set(at,[]);cuts.get(at).push({type,e});};
    for(const e of list){const a=Math.max(e.start,left),b=Math.min(e.end,right);if(b>a){add(a,1,e);add(b,-1,e);}}
    const points=[...cuts.keys()].sort((a,b)=>a-b),active=new Map(),totals={};
    let total=0;
    for(let i=0;i<points.length-1;i++){
      const t=points[i];for(const {type,e} of cuts.get(t)){if(type===1)active.set(e.key,e);else active.delete(e.key);}
      const span=points[i+1]-t;if(!active.size||span<=0)continue;
      const ids=new Set([...active.values()].map(e=>e.category));
      const id=ids.size===1?[...ids][0]:CONFLICT.id;
      totals[id]=(totals[id]||0)+span;total+=span;
    }
    return {total,totals};
  }
  const result=sweep(elapsed,bounds.start,now);
  const scheduled=sweep(upcoming,Math.max(bounds.now,bounds.start),bounds.end);
  return {...result,scheduled,elapsed:elapsed.sort((a,b)=>b.start-a.start),upcoming:upcoming.sort((a,b)=>a.start-b.start)};
}
export function displayDuration(ms){const mins=Math.floor(Math.max(0,ms)/60000);return mins>=60?`${Math.floor(mins/60)}h${mins%60?' '+mins%60+'m':''}`:`${mins}m`;}
export function makeEventDraft({title,category,start,duration,tz}){
  if(!title?.trim())throw new Error('Describe the action you will take.');
  if(!Number.isInteger(duration)||duration<5||duration>480)throw new Error('Choose a duration between 5 and 480 minutes.');
  const ms=localToMs(start,tz);
  return {summary:title.trim(),start:{dateTime:new Date(ms).toISOString(),timeZone:tz},end:{dateTime:new Date(ms+duration*60000).toISOString(),timeZone:tz},extendedProperties:{private:{timeLedgerCategory:category}}};
}
