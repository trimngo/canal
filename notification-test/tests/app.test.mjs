import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
process.env.TZ='Europe/Berlin';
const root=new URL('../web/',import.meta.url);
const source=(await Promise.all(['config.mjs','timeline.mjs','google.mjs','app.mjs'].map(f=>readFile(new URL(f,root),'utf8')))).map(s=>s.replace(/^import .*;\n/gm,'').replace(/^export /gm,'')).join('\n');
class Element{
  constructor(){this.value='';this.hidden=false;this.disabled=false;this.innerHTML='';this.textContent='';this.open=false;this.style={};this.handlers={};this.classList={toggle(){}};}
  addEventListener(type,fn){this.handlers[type]=fn;}
  replaceChildren(){this.innerHTML='';}
  showModal(){this.open=true;}
  close(){this.open=false;this.handlers.close?.();}
  querySelector(){return this.closeButton||=new Element();}
}
function storage(){const data=new Map();return {getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v),removeItem:k=>data.delete(k)};}
function fixture(){
  const elements=new Map(),el=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
  el('gap-form').elements=['activity','start','end','destination','save','check'].map(el);
  const calendars=[{id:'primary@test.example',primary:true,summary:'Personal',accessRole:'owner',selected:true},{id:'other@test.example',summary:'Work',accessRole:'reader',selected:true}];
  const make=(id,summary,start,end)=>({id,summary,start:{dateTime:start},end:{dateTime:end}});
  const rows={
    'primary@test.example':[make('morning','Planning','2026-10-13T07:00Z','2026-10-13T08:00Z'),make('ongoing','Writing','2026-10-13T09:00Z','2026-10-13T11:00Z'),make('future','Future appointment','2026-10-13T12:00Z','2026-10-13T13:00Z')],
    'other@test.example':[make('overlap','Call','2026-10-13T07:30Z','2026-10-13T08:30Z')]
  };
  const writes=[],deletes=[],requests=[],fixed=Date.parse('2026-10-13T10:00Z'),flags={readFailure:false,writeFailure:false,deleteFailure:null,changed:false};
  class Clock extends Date{constructor(...args){super(...(args.length?args:[fixed]));}static now(){return fixed;}}
  const google={accounts:{oauth2:{initTokenClient(options){return {requestAccessToken(){options.callback({access_token:'synthetic-token',expires_in:3600,scope:options.scope});}};},hasGrantedAllScopes(r,...scopes){return scopes.every(s=>r.scope.split(' ').includes(s));},revoke(token,callback){callback();}}}};
  const context=vm.createContext({document:{getElementById:el,querySelector:()=>el('summary'),addEventListener(){},hidden:false},window:{google},google,navigator:{},Intl,Date:Clock,URLSearchParams,crypto,localStorage:storage(),sessionStorage:storage(),setInterval(){},setTimeout,console,fetch:async(url,options)=>{
    const u=new URL(url);requests.push(u);assert.equal(u.origin,'https://www.googleapis.com');assert.equal(options.headers.Authorization,'Bearer synthetic-token');
    if(u.pathname.endsWith('calendarList'))return Response.json({items:calendars});
    const match=u.pathname.match(/\/calendars\/([^/]+)\/events(?:\/([^/]+))?$/),calendar=decodeURIComponent(match[1]),id=match[2];
    if(options.method==='DELETE'){
      deletes.push({calendar,id,options});
      if(flags.deleteFailure==='before'){flags.deleteFailure=null;throw new TypeError('Offline before deletion');}
      rows[calendar]=rows[calendar].filter(e=>e.id!==id);
      if(flags.deleteFailure==='after'){flags.deleteFailure=null;throw new TypeError('Response lost after deletion');}
      return new Response(null,{status:204});
    }
    if(options.method==='POST'){
      const body=JSON.parse(options.body);writes.push(body);if(flags.writeFailure){flags.writeFailure=false;throw new TypeError('Synthetic offline');}
      rows[calendar].push({...body,status:'confirmed'});return Response.json({...body,status:'confirmed'});
    }
    if(id){const found=rows[calendar].find(e=>e.id===id);return Response.json(found?(flags.changed?{...found,summary:'Changed elsewhere'}:found):{error:{message:'Not found'}},{status:found?200:404});}
    assert.equal(u.searchParams.get('timeMin'),'2026-10-12T22:00:00.000Z');assert.equal(u.searchParams.get('timeMax'),'2026-10-13T10:00:00.000Z');
    if(flags.readFailure&&calendar==='other@test.example')return Response.json({error:{message:'Synthetic failure'}},{status:503});
    return Response.json({items:rows[calendar]});
  }});
  vm.runInContext(source+'\nglobalThis.actions={connect,sync,openGap,saveGap,checkSave,openDelete,confirmDelete,checkDeletion,state:()=>({pending,pendingDelete,deletingEvent,ready,saving,selected})};',context);
  return {el,actions:context.actions,flags,writes,deletes,requests,rows};
}
test('today screen reads directly, excludes future time, splits gaps, and preserves IDs through uncertain-save recovery',async()=>{
  const {el,actions,flags,writes}=fixture();await actions.connect();
  assert.equal(el('recorded').textContent,'2h 30m');assert.equal(el('missing').textContent,'9h 30m');assert.doesNotMatch(el('timeline').innerHTML,/Future appointment/);assert.match(el('timeline').innerHTML,/Overlap counted once/);
  actions.openGap(0);el('activity').value='Sleeping';el('end').value='2026-10-13T08:00:00';await actions.saveGap({preventDefault(){}});
  assert.equal(writes.length,1);assert.equal(writes[0].start.timeZone,'Europe/Berlin');assert.equal(el('recorded').textContent,'10h 30m');assert.equal(el('missing').textContent,'1h 30m');
  actions.openGap(1);el('activity').value='Breakfast';flags.writeFailure=true;await actions.saveGap({preventDefault(){}});
  assert.equal(writes.length,2);assert.ok(actions.state().pending);assert.equal(el('save').disabled,true);
  await actions.checkSave();assert.equal(actions.state().pending,null);assert.equal(el('save').disabled,false);
  await actions.saveGap({preventDefault(){}});assert.equal(writes.length,3);assert.equal(writes[1].id,writes[2].id);assert.equal(el('recorded').textContent,'11h 30m');assert.equal(el('missing').textContent,'30m');
  flags.readFailure=true;await actions.sync();assert.equal(actions.state().ready,false);assert.equal(el('timeline').innerHTML,'');assert.match(el('message').textContent,/Could not read all/);
  flags.readFailure=false;await actions.sync();assert.equal(actions.state().ready,true);
});
test('validation prevents unnamed and future activities from creating events',async()=>{
  const {el,actions,writes}=fixture();await actions.connect();actions.openGap(0);
  await actions.saveGap({preventDefault(){}});assert.equal(writes.length,0);assert.match(el('save-error').textContent,/Enter what/);
  el('activity').value='Future work';el('end').value='2026-10-13T13:00:00';await actions.saveGap({preventDefault(){}});assert.equal(writes.length,0);assert.match(el('save-error').textContent,/inside this/);
});
test('deletion requires explicit confirmation, respects read-only calendars, and exposes only newly uncovered time',async()=>{
  const {el,actions,deletes}=fixture();await actions.connect();
  actions.openDelete(JSON.stringify(['other@test.example','overlap']));assert.equal(actions.state().deletingEvent,null);assert.equal(deletes.length,0);assert.match(el('timeline').innerHTML,/Read only/);
  actions.openDelete(JSON.stringify(['primary@test.example','morning']));assert.equal(deletes.length,0);assert.equal(el('delete-dialog').open,true);assert.equal(el('delete-name').textContent,'Planning');
  await actions.confirmDelete();assert.equal(deletes.length,1);assert.equal(deletes[0].id,'morning');assert.equal(el('delete-dialog').open,false);assert.equal(el('recorded').textContent,'2h');assert.equal(el('missing').textContent,'10h');
  assert.match(el('timeline').innerHTML,/Call/);assert.doesNotMatch(el('timeline').innerHTML,/Planning/);
});
test('uncertain deletion is checked without replaying the destructive request',async()=>{
  const {el,actions,deletes,flags}=fixture();await actions.connect();actions.openDelete(JSON.stringify(['primary@test.example','ongoing']));flags.deleteFailure='after';await actions.confirmDelete();
  assert.equal(deletes.length,1);assert.ok(actions.state().pendingDelete);assert.equal(el('delete-confirm').disabled,true);assert.equal(el('recorded').textContent,'2h 30m');
  await actions.checkDeletion();assert.equal(deletes.length,1);assert.equal(actions.state().pendingDelete,null);assert.equal(el('recorded').textContent,'1h 30m');assert.equal(el('missing').textContent,'10h 30m');
});
test('unsuccessful deletion can be retried only after checking that the event still exists',async()=>{
  const {el,actions,deletes,flags}=fixture();await actions.connect();actions.openDelete(JSON.stringify(['primary@test.example','ongoing']));flags.deleteFailure='before';await actions.confirmDelete();
  await actions.confirmDelete();assert.equal(deletes.length,1);await actions.checkDeletion();assert.equal(deletes.length,1);assert.equal(actions.state().pendingDelete,null);assert.match(el('delete-error').textContent,/still has this event/);
  await actions.confirmDelete();assert.equal(deletes.length,2);assert.equal(el('recorded').textContent,'1h 30m');
});
test('changed events are retained until reviewed again; recurring deletion targets only the displayed instance',async()=>{
  const {el,actions,deletes,flags,rows}=fixture();rows['primary@test.example'][0].recurringEventId='parent-series';await actions.connect();
  actions.openDelete(JSON.stringify(['primary@test.example','morning']));assert.equal(el('delete-recurring').hidden,false);
  flags.changed=true;await actions.confirmDelete();assert.equal(deletes.length,0);assert.match(el('delete-error').textContent,/changed in Google/);
  flags.changed=false;await actions.confirmDelete();assert.equal(deletes.length,1);assert.equal(deletes[0].id,'morning');assert.notEqual(deletes[0].id,'parent-series');
});
