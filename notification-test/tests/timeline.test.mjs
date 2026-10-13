import test from 'node:test';
import assert from 'node:assert/strict';
import {todayBounds,accountDay,normalize,makeGapEvent,localToMs} from '../web/timeline.mjs';
const calendar={id:'primary',summary:'Calendar'};
const ms=s=>Date.parse(s);
const event=(id,start,end,extra={})=>normalize({id,summary:id,start:{dateTime:start},end:{dateTime:end},...extra},calendar);
test('midnight to now is completely partitioned; upcoming events are excluded and ongoing events clipped',()=>{
  const bounds=todayBounds(ms('2026-10-13T12:00:00Z'),'UTC');
  const data=accountDay([event('morning','2026-10-13T08:00Z','2026-10-13T09:00Z'),event('ongoing','2026-10-13T11:00Z','2026-10-13T13:00Z'),event('future','2026-10-13T15:00Z','2026-10-13T16:00Z')],bounds);
  assert.equal(data.recorded,2*3600000);assert.equal(data.missing,10*3600000);assert.equal(data.recorded+data.missing,data.elapsed);
  assert.equal(data.segments[0].start,bounds.start);assert.equal(data.segments.at(-1).end,bounds.end);
  data.segments.forEach((s,i)=>{if(i)assert.equal(s.start,data.segments[i-1].end);assert.ok(s.end>s.start);assert.ok(s.end<=bounds.end);assert.ok(s.events.every(e=>e.id!=='future'));});
});
test('overlaps count once, duplicate calendar invitations collapse, and overnight events are clipped',()=>{
  const first=event('one','2026-10-12T22:00Z','2026-10-13T02:00Z',{iCalUID:'shared'}),copy={...first,key:first.key,calendarId:'other'};
  const data=accountDay([first,copy,event('two','2026-10-13T01:00Z','2026-10-13T03:00Z')],todayBounds(ms('2026-10-13T06:00Z'),'UTC'));
  assert.equal(data.recorded,3*3600000);assert.equal(data.missing,3*3600000);assert.equal(data.segments.filter(s=>s.events.length===2).length,1);
});
test('all-day labels are shown without covering time; cancelled and declined events do not fill gaps',()=>{
  const allDay=normalize({id:'reminder',summary:'Birthday',start:{date:'2026-10-13'},end:{date:'2026-10-14'}},calendar);
  assert.equal(event('cancelled','2026-10-13T01:00Z','2026-10-13T02:00Z',{status:'cancelled'}),null);
  assert.equal(event('declined','2026-10-13T01:00Z','2026-10-13T02:00Z',{attendees:[{self:true,responseStatus:'declined'}]}),null);
  const data=accountDay([allDay],todayBounds(ms('2026-10-13T12:00Z'),'UTC'));assert.equal(data.allDay.length,1);assert.equal(data.recorded,0);assert.equal(data.missing,12*3600000);
});
test('a partial gap entry leaves the remainder unrecorded and rejects writes beyond the gap or now',()=>{
  const bounds=todayBounds(ms('2026-10-13T12:00Z'),'UTC'),gap={start:bounds.start,end:bounds.end};
  const input={title:'Sleeping',start:'2026-10-13T00:00',end:'2026-10-13T08:00',gap,bounds,tz:'UTC',id:'tl123'};
  const draft=makeGapEvent(input);assert.equal(draft.id,'tl123');assert.equal(draft.summary,'Sleeping');
  const data=accountDay([normalize(draft,calendar)],bounds);assert.equal(data.recorded,8*3600000);assert.equal(data.missing,4*3600000);
  for(const change of [{title:' '},{start:'2026-10-12T23:00'},{end:'2026-10-13T13:00'},{start:'2026-10-13T08:00',end:'2026-10-13T08:00'}])assert.throws(()=>makeGapEvent({...input,...change}));
});
test('local day boundaries follow the phone timezone including spring and autumn clock changes',()=>{
  const normal=todayBounds(ms('2026-10-13T10:00Z'),'Europe/Berlin');assert.equal(normal.start,ms('2026-10-12T22:00Z'));
  const spring=todayBounds(ms('2026-03-29T21:59:59Z'),'Europe/Berlin');assert.equal(spring.end-spring.start,23*3600000-1000);
  const autumn=todayBounds(ms('2026-10-25T22:59:59Z'),'Europe/Berlin');assert.equal(autumn.end-autumn.start,25*3600000-1000);
  assert.throws(()=>localToMs('2026-03-29T02:30','Europe/Berlin'),/clocks changed/);
  assert.equal(localToMs('2026-10-25T02:30','Europe/Berlin',{start:ms('2026-10-25T01:00Z'),end:ms('2026-10-25T02:00Z')}),ms('2026-10-25T01:30Z'));
});
test('midnight starts with an empty elapsed day; every segment uses a unique interval',()=>{
  const bounds=todayBounds(ms('2026-10-13T00:00Z'),'UTC'),data=accountDay([],bounds);
  assert.equal(data.elapsed,0);assert.equal(data.missing,0);assert.equal(data.segments.length,0);
});
