export const INTERVAL=15*60000;
export function localStamp(ms,tz){
 const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(ms).map(p=>[p.type,p.value]));
 return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}:${p.second}`;
}
export function localToMs(value,tz){
 const full=value.length===16?value+':00':value,guess=Date.parse(full+'Z'),matches=[];
 for(const d of [-36,-12,0,12,36]){const probe=guess+d*3600000,offset=Date.parse(localStamp(probe,tz)+'Z')-probe,candidate=guess-offset;if(localStamp(candidate,tz)===full)matches.push(candidate);}
 if(!matches.length)throw new Error('That date or time does not exist in this timezone.');return Math.min(...matches);
}
export function validDate(value){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;const parsed=new Date(value+'T12:00:00Z');return Number.isFinite(parsed.getTime())&&parsed.toISOString().slice(0,10)===value;}
export function dayBounds(date,tz){
 if(!validDate(date))throw new Error('Choose a valid date.');const next=new Date(date+'T12:00:00Z');next.setUTCDate(next.getUTCDate()+1);
 return {start:localToMs(date+'T00:00',tz),end:localToMs(next.toISOString().slice(0,10)+'T00:00',tz)};
}
export function formatTime(ms,tz,format='12'){return new Intl.DateTimeFormat(format==='12'?'en-US':'en-GB',{timeZone:tz,hour:format==='12'?'numeric':'2-digit',minute:'2-digit',hour12:format==='12'}).format(ms);}
export function scheduleTime(minutes,format='12'){return formatTime(Date.UTC(2026,0,1,0,minutes),'UTC',format);}
export function slotEnd(now){return Math.floor(now/INTERVAL)*INTERVAL;}
export function scheduledSlot(now,settings){
 if(!settings.enabled)return null;const end=slotEnd(now),stamp=localStamp(end,settings.timezone);let minutes=Number(stamp.slice(11,13))*60+Number(stamp.slice(14,16));if(minutes===0&&settings.end_minute===1440)minutes=1440;
 return minutes>settings.start_minute&&minutes<=settings.end_minute?end:null;
}
export function slotsForDay(date,tz,now){
 const bounds=dayBounds(date,tz),slots=[];for(let end=bounds.start+INTERVAL;end<=Math.min(now,bounds.end);end+=INTERVAL)slots.push(end);return slots;
}
export function breakdown(entries,categories){
 const totals=new Map(categories.map(c=>[c.id,0]));let uncategorized=0;
 for(const e of entries){if(e.category_id&&totals.has(e.category_id))totals.set(e.category_id,totals.get(e.category_id)+15);else uncategorized+=15;}
 return {categories:categories.map(c=>({...c,minutes:totals.get(c.id),percent:totals.get(c.id)/1440*100})),uncategorized,unlogged:Math.max(0,1440-entries.length*15),logged:entries.length*15};
}
export function minutesLabel(mins){return mins>=60?`${Math.floor(mins/60)}h${mins%60?' '+mins%60+'m':''}`:`${mins}m`;}
