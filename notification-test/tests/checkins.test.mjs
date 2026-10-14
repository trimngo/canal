import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFile,readdir} from 'node:fs/promises';
import worker,{validateEndpoint} from '../worker/index.js';
import {tickCheckins} from '../worker/checkins.mjs';
import {scheduledSlot,breakdown,INTERVAL,dayBounds,slotsForDay} from '../checkins/core.mjs';
const migrationDir=new URL('../drizzle/',import.meta.url);
const migrations=await Promise.all((await readdir(migrationDir)).filter(f=>f.endsWith('.sql')).sort().map(f=>readFile(new URL(f,migrationDir),'utf8')));
function database(){
 const sqlite=new DatabaseSync(':memory:');for(const sql of migrations)sqlite.exec(sql);
 const db={prepare(sql){return {sql,params:[],bind(...params){this.params=params;return this;},async first(){return sqlite.prepare(sql).get(...this.params)||null;},async all(){return {results:sqlite.prepare(sql).all(...this.params)};},async run(){const r=sqlite.prepare(sql).run(...this.params);return {meta:{changes:Number(r.changes)}};}};},async batch(statements){sqlite.exec('BEGIN');try{const results=[];for(const s of statements)results.push(await s.run());sqlite.exec('COMMIT');return results;}catch(e){sqlite.exec('ROLLBACK');throw e;}}};return {db,sqlite};
}
function request(path,data,user='alice',headers={}){return new Request('https://test.example'+path,{method:data===undefined?'GET':'POST',headers:{'oai-authenticated-user-id':user,...(data===undefined?{}:{Origin:'https://test.example','Content-Type':'application/json'}),...headers},...(data===undefined?{}:{body:JSON.stringify(data)})});}
async function state(env,user='alice'){const response=await worker.fetch(request('/api/checkins?date=2026-10-14',undefined,user),env,{});assert.equal(response.status,200);return response.json();}
test('default schedule runs 7:15 AM through 10 PM, follows timezone and clock changes, and honors pause',()=>{
 const settings={enabled:1,start_minute:420,end_minute:1320,timezone:'Europe/Berlin'};
 for(const day of ['2026-10-14','2026-03-29','2026-10-25']){
  const bounds=dayBounds(day,'Europe/Berlin'),offset=day==='2026-03-29'||day==='2026-10-14'?'+02:00':'+01:00';
  assert.equal(scheduledSlot(Date.parse(day+'T07:00:00'+offset),settings),null);assert.equal(scheduledSlot(Date.parse(day+'T07:15:10'+offset),settings),Date.parse(day+'T07:15:00'+offset));
  assert.equal(scheduledSlot(Date.parse(day+'T22:00:05'+offset),settings),Date.parse(day+'T22:00:00'+offset));assert.equal(scheduledSlot(Date.parse(day+'T22:15:00'+offset),settings),null);
  assert.ok(bounds.end>bounds.start);
 }
 assert.equal(scheduledSlot(Date.parse('2026-10-14T12:00Z'),{...settings,enabled:0}),null);
});
test('percentages use all 24 hours and missed samples never stretch the next answer',()=>{
 const rows=[{category_id:'classes'},{category_id:'classes'},{category_id:null}],stats=breakdown(rows,[{id:'classes',name:'Classes'}]);
 assert.equal(stats.categories[0].minutes,30);assert.equal(stats.categories[0].percent,30/1440*100);assert.equal(stats.uncategorized,15);assert.equal(stats.unlogged,1395);
 const slots=slotsForDay('2026-10-14','Europe/Berlin',Date.parse('2026-10-14T08:00Z'));assert.ok(slots.every((end,i)=>!i||end-slots[i-1]===INTERVAL));
});
test('answers persist, are isolated by account, allow later categorization, and reject stale or future edits',async()=>{
 const {db,sqlite}=database(),env={DB:db};const savedNow=Date.now;Date.now=()=>Date.parse('2026-10-14T10:00Z');
 try{
  await state(env);const end=Date.now()-INTERVAL;
  const create=await worker.fetch(request('/api/checkins/entry',{end,activity:'Preparing class',categoryId:null,version:0}),env,{});assert.equal(create.status,200);
  let data=await state(env);assert.equal(data.entries.length,1);assert.equal(data.entries[0].category_id,null);assert.equal(data.entries[0].start_ms,end-INTERVAL);
  const retry=await worker.fetch(request('/api/checkins/entry',{end,activity:'Preparing class',categoryId:null,version:0}),env,{});assert.equal(retry.status,200);assert.equal((await state(env)).entries.length,1);
  const edited=await worker.fetch(request('/api/checkins/entry',{end,activity:'Preparing class',categoryId:'classes',version:1}),env,{});assert.equal(edited.status,200);
  assert.equal((await state(env,'bob')).entries.length,0);
  assert.equal((await worker.fetch(request('/api/checkins/entry',{end,activity:'Changed',categoryId:null,version:1}),env,{})).status,409);
  assert.equal((await worker.fetch(request('/api/checkins/entry',{end:Date.now()+INTERVAL,activity:'Future',version:0}),env,{})).status,400);
  assert.equal((await worker.fetch(request('/api/checkins/entry',{end:Date.now(),activity:'Wrong category',categoryId:'not-mine',version:0}),env,{})).status,400);
  assert.equal((await worker.fetch(request('/api/checkins/category',{id:'classes',name:'Class preparation'}),env,{})).status,200);
  data=await state(env);assert.equal(data.categories.find(c=>c.id==='classes').name,'Class preparation');assert.equal(data.entries[0].activity,'Preparing class');
  const anon=request('/api/checkins');anon.headers.delete('oai-authenticated-user-id');assert.equal((await worker.fetch(anon,env,{})).status,401);
  assert.equal((await worker.fetch(request('/api/checkins/category',{name:'Cross-site'},'alice',{Origin:'https://other.example'}),env,{})).status,403);
 }finally{Date.now=savedNow;sqlite.close();}
});
test('settings are persistent and versioned; categories update labels without rewriting answers',async()=>{
 const {db,sqlite}=database(),env={DB:db};const savedNow=Date.now;Date.now=()=>Date.parse('2026-10-14T10:00Z');
 try{const initial=await state(env);assert.equal(initial.settings.start_minute,420);assert.equal(initial.settings.end_minute,1320);
  const payload={startMinute:480,endMinute:1260,enabled:false,timeFormat:'24',timezone:'Europe/Berlin',version:1};assert.equal((await worker.fetch(request('/api/checkins/settings',payload),env,{})).status,200);
  const next=await state(env);assert.equal(next.settings.enabled,0);assert.equal(next.settings.start_minute,480);assert.equal(next.settings.time_format,'24');
  assert.equal((await worker.fetch(request('/api/checkins/settings',payload),env,{})).status,409);
  assert.equal((await worker.fetch(request('/api/checkins/settings',{...payload,version:2,startMinute:481}),env,{})).status,400);
 }finally{Date.now=savedNow;sqlite.close();}
});
test('scheduler suppresses duplicates, expired subscriptions, paused schedules, and already-answered intervals',async()=>{
 const {db,sqlite}=database(),env={DB:db,CHECKIN_SCHEDULER_ENABLED:'1',CHECKIN_SCHEDULER_TOKEN:'synthetic-scheduler-token'};const savedNow=Date.now;Date.now=()=>Date.parse('2026-10-14T05:15:05Z');
 let calls=0;const services={validateEndpoint,sendPush:async()=>{calls++;return 201;}};
 try{
  await state(env);const deviceResponse=await worker.fetch(request('/api/checkins/device',{endpoint:'https://web.push.apple.com/synthetic-device'}),env,{});assert.equal(deviceResponse.status,200);const {id}=await deviceResponse.json();
  assert.equal((await tickCheckins(env,services)).accepted,1);assert.equal((await tickCheckins(env,services)).accepted,0);assert.equal(calls,1);
  const prompt=await (await worker.fetch(request('/api/checkins/prompt?device='+id),env,{})).json();assert.equal(prompt.slot,Date.parse('2026-10-14T05:15Z'));assert.match(prompt.body,/7:00 AM–7:15 AM/);
  assert.equal((await worker.fetch(request('/api/checkins/prompt?device='+id,undefined,'bob'),env,{})).status,404);
  assert.equal((await worker.fetch(request('/api/checkins/tick',{},'alice'),env,{})).status,403);
  Date.now=()=>Date.parse('2026-10-14T05:30:05Z');await worker.fetch(request('/api/checkins/entry',{end:Date.parse('2026-10-14T05:30Z'),activity:'Recorded already',version:0}),env,{});await tickCheckins(env,services);assert.equal(calls,1);
  Date.now=()=>Date.parse('2026-10-14T05:45:05Z');await tickCheckins(env,{...services,sendPush:async()=>{throw new Error('Subscription expired');}});assert.equal((await state(env)).devices[0].active,0);
 }finally{Date.now=savedNow;sqlite.close();}
});
test('the scheduler reports unavailable configuration rather than claiming reminders run',async()=>{
 const {db,sqlite}=database(),env={DB:db,CHECKIN_SCHEDULER_ENABLED:'0',CHECKIN_SCHEDULER_TOKEN:'synthetic-scheduler-token'};
 try{const response=await worker.fetch(request('/api/checkins/tick',{},'service',{'X-Checkin-Scheduler-Token':'synthetic-scheduler-token'}),env,{});assert.equal(response.status,200);assert.equal((await response.json()).configured,false);assert.equal((await state(env)).scheduler.configured,false);}finally{sqlite.close();}
});
