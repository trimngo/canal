import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const core=await readFile(new URL('../checkins/core.mjs',import.meta.url),'utf8'),client=await readFile(new URL('../checkins/app.mjs',import.meta.url),'utf8');
class Element{
 constructor(){this.value='';this.textContent='';this.innerHTML='';this.hidden=false;this.disabled=false;this.checked=false;this.open=false;this.handlers={};this.classList={toggle(){}};}
 setAttribute(){}addEventListener(t,f){this.handlers[t]=f;}showModal(){this.open=true;}close(){this.open=false;}
}
async function fixture(){
 const elements=new Map(),handlers={},el=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const now=Date.parse('2026-10-14T10:00Z'),end=now,settings={timezone:'Europe/Berlin',start_minute:420,end_minute:1320,enabled:1,time_format:'12',version:1},categories=[{id:'classes',name:'Classes',color:'#315eec'}],entries=[],requests=[];
 class Clock extends Date{constructor(...args){super(...(args.length?args:[now]));}static now(){return now;}}
 const intl={DateTimeFormat:(locale,options)=>new Intl.DateTimeFormat(locale,{...(!options?.timeZone?{timeZone:'Europe/Berlin'}:{}),...options})};
 // Intl.DateTimeFormat must also be constructible.
 intl.DateTimeFormat=function(locale,options){return new Intl.DateTimeFormat(locale,{...(!options?.timeZone?{timeZone:'Europe/Berlin'}:{}),...options});};
 const context=vm.createContext({document:{getElementById:el,addEventListener(type,fn){handlers[type]=fn;},querySelector(){return null;},querySelectorAll(){return ['edit-dialog','settings-dialog','rename-dialog'].map(el);},hidden:false},navigator:{userAgent:'test',platform:'test',maxTouchPoints:0},window:{},matchMedia:()=>({matches:false}),Intl:intl,Date:Clock,URLSearchParams,location:{search:''},setInterval(){},setTimeout,console,fetch:async(path,options)=>{
  const body=options.body?JSON.parse(options.body):null;requests.push({path,body});
  if(!body)return Response.json({userId:'alice',date:'2026-10-14',settings:{...settings},categories:structuredClone(categories),entries:structuredClone(entries),slots:[end-900000,end],scheduler:{configured:false,lastTick:null},devices:[],publicKey:null,now});
  if(path==='/api/checkins/entry'){const existing=entries.find(e=>e.end_ms===body.end);if(existing)Object.assign(existing,{activity:body.activity,category_id:body.categoryId,version:existing.version+1});else entries.push({end_ms:body.end,start_ms:body.end-900000,activity:body.activity,category_id:body.categoryId,version:1});return Response.json({saved:true});}
  if(path==='/api/checkins/settings'){Object.assign(settings,{start_minute:body.startMinute,end_minute:body.endMinute,enabled:body.enabled?1:0,time_format:body.timeFormat,timezone:body.timezone,version:settings.version+1});return Response.json({saved:true});}
  if(path==='/api/checkins/category'){const c=categories.find(c=>c.id===body.id);if(c)c.name=body.name;return Response.json({saved:true});}
  throw new Error('Unexpected test request');
 }});
 vm.runInContext(core.replace(/^export /gm,'')+'\n'+client.replace(/^import .*;\n/gm,''),context);
 for(let i=0;i<20&&el('save-answer').disabled;i++)await new Promise(r=>setImmediate(r));
 return {el,entries,settings,requests,handlers};
}
test('phone flow saves a check-in without a category and displays the uncategorized inbox and 24-hour percentage',async()=>{
 const {el,entries}=await fixture();assert.equal(el('prompt-period').textContent,'11:45 AM–12:00 PM');
 el('activity').value='Preparing class';el('category').value='';await el('answer-form').onsubmit({preventDefault(){}});
 assert.equal(entries.length,1);assert.equal(entries[0].category_id,null);assert.match(el('entries').innerHTML,/Preparing class/);assert.match(el('uncategorized-filter').textContent,/1/);assert.match(el('breakdown').innerHTML,/15m · 1.0%/);assert.match(el('reminder-status').textContent,/scheduler setup/);
});
test('edited reminder hours and pause settings are captured before the UI rerenders',async()=>{
 const {el,settings,requests}=await fixture();el('start-time').value='08:00';el('end-time').value='21:00';el('reminders-enabled').checked=false;el('time-format').value='24';
 await el('settings-form').onsubmit({preventDefault(){}});const posted=requests.find(r=>r.path==='/api/checkins/settings').body;
 assert.equal(posted.startMinute,480);assert.equal(posted.endMinute,1260);assert.equal(posted.enabled,false);assert.equal(posted.timeFormat,'24');assert.equal(settings.enabled,0);assert.equal(el('reminder-status').textContent,'Reminders paused');
});
test('category rename changes every displayed label while preserving the saved activity',async()=>{
 const {el,entries,handlers}=await fixture();el('activity').value='Preparing class';el('category').value='classes';await el('answer-form').onsubmit({preventDefault(){}});
 handlers.click({target:{closest:selector=>selector==='[data-rename]'?{dataset:{rename:'classes'}}:null}});assert.equal(el('rename-dialog').open,true);
 el('rename-name').value='Class preparation';await el('rename-form').onsubmit({preventDefault(){}});
 assert.equal(entries[0].activity,'Preparing class');assert.equal(entries[0].category_id,'classes');assert.match(el('entries').innerHTML,/Class preparation/);
});
