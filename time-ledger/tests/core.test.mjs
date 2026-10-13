import test from 'node:test';
import assert from 'node:assert/strict';
import {periodBounds,localToMs,normalizeEvent,allocate,classify,makeEventDraft,DEFAULT_CATEGORIES} from '../dist/core.mjs';
const base=Date.parse('2026-10-12T08:00:00Z');
const event=(id,a,b,extra={})=>({id,key:id,uid:id,start:base+a*60000,end:base+b*60000,title:'[Product] Build',...extra});
const bounds={start:base,end:base+480*60000,now:base+120*60000};
test('elapsed intervals stop at now and future portions stay separate',()=>{
 const result=allocate([event('ongoing',60,180),event('future',240,270)],bounds,DEFAULT_CATEGORIES);
 assert.equal(result.total,60*60000);assert.equal(result.scheduled.total,90*60000);assert.equal(result.upcoming.length,2);
});
test('conflicting overlap counts once under a visible overlap category',()=>{
 const result=allocate([event('a',0,90),event('b',30,120,{title:'[Clients] Outreach'})],bounds,DEFAULT_CATEGORIES);
 assert.equal(result.total,120*60000);assert.deepEqual(result.totals,{product:30*60000,overlap:60*60000,clients:30*60000});
 assert.equal(Object.values(result.totals).reduce((a,b)=>a+b,0),result.total);
});
test('same-category overlap and duplicate copies never inflate totals',()=>{
 const a=event('a',0,90);const result=allocate([a,{...a,calendarId:'other'},event('b',30,120)],bounds,DEFAULT_CATEGORIES);
 assert.equal(result.total,120*60000);assert.equal(result.totals.product,120*60000);assert.equal(result.elapsed.length,2);
});
test('event and series overrides beat ambiguous matching words',()=>{
 const e=event('a',0,30,{title:'Client product review',seriesKey:'series'});
 assert.equal(classify(e,DEFAULT_CATEGORIES).category,'uncategorized');
 assert.equal(classify(e,DEFAULT_CATEGORIES,{a:'learning'},{series:'team'}).category,'learning');
 assert.equal(classify(e,DEFAULT_CATEGORIES,{}, {series:'team'}).category,'team');
 assert.equal(classify({...e,title:'Research proposal'},DEFAULT_CATEGORIES).category,'uncategorized');
 assert.equal(classify({...e,title:'[Clients] Product demo'},DEFAULT_CATEGORIES).category,'clients');
});
test('keyword matching uses word boundaries instead of partial words',()=>{
 assert.equal(classify(event('a',0,30,{title:'Chairmanship review'}),[{id:'x',name:'Chair',keywords:['chair']}]).category,'uncategorized');
 assert.equal(classify(event('a',0,30,{title:'A C++ lesson'}),[{id:'x',name:'Code',keywords:['c++']}]).category,'x');
});
test('all-day, canceled, declined, and informational events do not become work hours',()=>{
 const calendar={id:'primary'},raw={id:'a',start:{dateTime:'2026-10-12T08:00Z'},end:{dateTime:'2026-10-12T09:00Z'}};
 assert.ok(normalizeEvent(raw,calendar));
 assert.equal(normalizeEvent({...raw,status:'cancelled'},calendar),null);
 assert.equal(normalizeEvent({...raw,attendees:[{self:true,responseStatus:'declined'}]},calendar),null);
 assert.equal(normalizeEvent({...raw,start:{date:'2026-10-12'},end:{date:'2026-10-13'}},calendar),null);
 assert.equal(normalizeEvent({...raw,eventType:'workingLocation'},calendar),null);
 assert.equal(normalizeEvent({...raw,eventType:'outOfOffice'},calendar),null);
});
test('local day boundaries and Monday week boundaries account for DST',()=>{
 const date=Date.parse('2026-10-25T12:00:00Z');
 const day=periodBounds(date,'Europe/Berlin');assert.equal(day.end-day.start,25*3600000);
 const week=periodBounds(date,'Europe/Berlin','week');assert.equal(week.startDate,'2026-10-19');assert.equal(week.end-week.start,169*3600000);
 const spring=periodBounds(Date.parse('2026-03-29T12:00Z'),'Europe/Berlin');assert.equal(spring.end-spring.start,23*3600000);
});
test('nonexistent local start times are rejected; ambiguous times are deterministic',()=>{
 assert.throws(()=>localToMs('2026-03-29T02:30','Europe/Berlin'),/does not exist/);
 assert.equal(new Date(localToMs('2026-10-25T02:30','Europe/Berlin')).toISOString(),'2026-10-25T00:30:00.000Z');
});
test('cross-boundary events contribute only their clipped portions',()=>{
 const result=allocate([event('a',-30,30),event('b',110,160)],bounds,DEFAULT_CATEGORIES);
 assert.equal(result.total,40*60000);assert.equal(result.scheduled.total,40*60000);
});
test('event drafts require an action and have exact timezone-aware duration',()=>{
 const d=makeEventDraft({title:'  Draft outreach  ',category:'clients',start:'2026-10-12T14:00',duration:30,tz:'Europe/Berlin'});
 assert.equal(d.summary,'Draft outreach');assert.equal(d.start.dateTime,'2026-10-12T12:00:00.000Z');assert.equal(Date.parse(d.end.dateTime)-Date.parse(d.start.dateTime),1800000);assert.equal(d.extendedProperties.private.timeLedgerCategory,'clients');
 assert.throws(()=>makeEventDraft({title:' ',duration:30,start:'2026-10-12T14:00',tz:'Europe/Berlin'}));
 assert.throws(()=>makeEventDraft({title:'Work',duration:4,start:'2026-10-12T14:00',tz:'Europe/Berlin'}));
});
