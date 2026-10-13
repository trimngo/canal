export function localStamp(ms, tz) {
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(ms).map(p=>[p.type,p.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}`;
}
export function localToMs(value,tz,range=null) {
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(value))throw new Error('Choose a valid time.');
  const full=value.length===16?value+':00':value,guess=Date.parse(full+'Z'),candidates=[];
  if(!Number.isFinite(guess))throw new Error('Choose a valid time.');
  for(const delta of [-36,-12,0,12,36]){
    const probe=guess+delta*3600000,offset=Date.parse(localStamp(probe,tz)+'Z')-probe,candidate=guess-offset;
    if(localStamp(candidate,tz)===full)candidates.push(candidate);
  }
  if(!candidates.length)throw new Error('That time does not exist because the clocks changed.');
  const allowed=range?candidates.filter(ms=>ms>=range.start&&ms<=range.end):candidates;
  if(!allowed.length)throw new Error('Keep the activity inside this unrecorded period, before now.');
  return Math.min(...allowed);
}
export function todayBounds(now,tz) {
  const date=localStamp(now,tz).slice(0,10);
  return {date,start:localToMs(date+'T00:00',tz),end:Math.floor(now/1000)*1000};
}
export function duration(ms) {
  if(ms>0&&ms<60000)return '<1m';
  const m=Math.floor(Math.max(0,ms)/60000);
  return m>=60?`${Math.floor(m/60)}h${m%60?' '+m%60+'m':''}`:`${m}m`;
}
export function normalize(raw,calendar) {
  if(raw.status==='cancelled'||raw.attendees?.some(a=>a.self&&a.responseStatus==='declined'))return null;
  const base={id:raw.id,calendarId:calendar.id,calendarName:calendar.summary||calendar.id,title:raw.summary?.trim()||'Untitled event',url:raw.htmlLink||null,updated:Date.parse(raw.updated||'')||0};
  if(raw.start?.date&&raw.end?.date)return {...base,allDay:true,startDate:raw.start.date,endDate:raw.end.date,key:JSON.stringify([raw.iCalUID||calendar.id+':'+raw.id,raw.start.date])};
  const start=Date.parse(raw.start?.dateTime),end=Date.parse(raw.end?.dateTime);
  if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return null;
  return {...base,start,end,key:JSON.stringify([raw.iCalUID||calendar.id+':'+raw.id,start]),allDay:false};
}
// Partition every instant from midnight to now. Overlapping events count once;
// all-day labels never imply that all 24 hours were actually spent on an activity.
export function accountDay(events,bounds) {
  const unique=new Map();
  for(const e of events){const old=unique.get(e.key);if(!old||e.updated>old.updated)unique.set(e.key,e);}
  const all=[...unique.values()],allDay=all.filter(e=>e.allDay&&e.startDate<=bounds.date&&e.endDate>bounds.date);
  const timed=all.filter(e=>!e.allDay&&e.start<bounds.end&&e.end>bounds.start);
  const points=[...new Set([bounds.start,bounds.end,...timed.flatMap(e=>[Math.max(bounds.start,e.start),Math.min(bounds.end,e.end)])])].sort((a,b)=>a-b);
  const segments=[];let recorded=0,missing=0;
  for(let i=0;i<points.length-1;i++){
    const start=points[i],end=points[i+1];if(end<=start)continue;
    const active=timed.filter(e=>e.start<end&&e.end>start).sort((a,b)=>a.start-b.start||a.key.localeCompare(b.key));
    const signature=JSON.stringify(active.map(e=>e.key)),last=segments.at(-1);
    if(last&&last.signature===signature&&last.end===start)last.end=end;
    else segments.push({start,end,events:active,kind:active.length?'event':'gap',signature});
    if(active.length)recorded+=end-start;else missing+=end-start;
  }
  return {segments,allDay,recorded,missing,elapsed:Math.max(0,bounds.end-bounds.start),gaps:segments.filter(s=>s.kind==='gap')};
}
export function makeGapEvent({title,start,end,gap,bounds,tz,id}) {
  if(!title?.trim())throw new Error('Enter what you were doing.');
  if(title.trim().length>200)throw new Error('Keep the activity under 200 characters.');
  const a=localToMs(start,tz,gap),b=localToMs(end,tz,{start:a+1,end:gap.end});
  if(b<=a)throw new Error('End time must be after start time.');
  if(a<gap.start||b>gap.end||a<bounds.start||b>bounds.end)throw new Error('Keep the activity inside this unrecorded period, before now.');
  return {id,summary:title.trim(),start:{dateTime:new Date(a).toISOString(),timeZone:tz},end:{dateTime:new Date(b).toISOString(),timeZone:tz},extendedProperties:{private:{timeLedgerSource:'gap-review'}}};
}
