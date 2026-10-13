import test from 'node:test';
import assert from 'node:assert/strict';
import {calendarRequest,listCalendars,listEvents,createEvent} from '../web/google.mjs';
test('reads use fixed Google API origin, bearer authorization, and pagination',async()=>{
 const original=globalThis.fetch,calls=[];
 try{
 globalThis.fetch=async(url,options)=>{calls.push({url,options});return Response.json(calls.length===1?{items:[{id:'one'}],nextPageToken:'next'}:{items:[{id:'two'}]});};
 const rows=await listCalendars('test-only');assert.equal(rows.length,2);assert.match(calls[1].url,/pageToken=next/);assert.equal(calls[0].options.headers.Authorization,'Bearer test-only');assert.equal(calls[0].options.method,'GET');assert.equal(calls[0].options.cache,'no-store');
 }finally{globalThis.fetch=original;}
});
test('expired sessions surface an actionable error without replaying requests',async()=>{
 const original=globalThis.fetch;let calls=0;try{globalThis.fetch=async()=>{calls++;return Response.json({error:{message:'Expired'}},{status:401});};await assert.rejects(()=>calendarRequest('test-only','users/me/calendarList'),e=>e.status===401&&/expired/.test(e.message));assert.equal(calls,1);}finally{globalThis.fetch=original;}
});
test('event queries are bounded and expand recurring instances',async()=>{
 const original=globalThis.fetch;let requested;try{globalThis.fetch=async url=>{requested=new URL(url);return Response.json({items:[]});};await listEvents('test-only','cal@example.com',0,3600000);assert.equal(requested.searchParams.get('singleEvents'),'true');assert.equal(requested.searchParams.get('timeMin'),'1970-01-01T00:00:00.000Z');assert.match(requested.pathname,/cal%40example.com/);}finally{globalThis.fetch=original;}
});
test('writes occur once and unknown completion is never represented as saved',async()=>{
 const original=globalThis.fetch;let count=0;try{globalThis.fetch=async()=>{count++;throw new TypeError('Offline');};await assert.rejects(()=>createEvent('test-only','primary',{id:'tl123',summary:'Work'}),e=>e.uncertain===true);assert.equal(count,1);globalThis.fetch=async()=>Response.json({summary:'No ID'});await assert.rejects(()=>createEvent('test-only','primary',{}),e=>e.uncertain===true);}finally{globalThis.fetch=original;}
});
test('only confirmed provider event IDs yield write success',async()=>{
 const original=globalThis.fetch;try{globalThis.fetch=async(url,options)=>{assert.equal(options.method,'POST');assert.equal(JSON.parse(options.body).id,'tl123');return Response.json({id:'tl123',status:'confirmed'});};assert.equal((await createEvent('test-only','primary',{id:'tl123'})).id,'tl123');}finally{globalThis.fetch=original;}
});
