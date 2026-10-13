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
  const writes=[],requests=[],fixed=Date.parse('2026-10-13T10:00Z'),flags={readFailure:false,writeFailure:false};
  class Clock extends Date{constructor(...args){super(...(args.length?args:[fixed]));}static now(){return fixed;}}
  const google={accounts:{oauth2:{initTokenClient(options){return {requestAccessToken(){options.callback({access_token:'synthetic-token',expires_in:3600,scope:options.scope});}};},hasGrantedAllScopes(r,...scopes){return scopes.every(s=>r.scope.split(' ').includes(s));},revoke(token,callback){callback();}}}};
  const context=vm.createContext({document:{getElementById:el,querySelector:()=>el('summary'),addEventListener(){},hidden:false},window:{google},google,navigator:{},Intl,Date:Clock,URLSearchParams,crypto,localStorage:storage(),sessionStorage:storage(),setInterval(){},setTimeout,console,fetch:async(url,options)=>{
    const u=new URL(url);requests.push(u);assert.equal(u.origin,'https://www.googleapis.com');assert.equal(options.headers.Authorization,'Bearer synthetic-token');
    if(u.pathname.endsWith('calendarList'))return Response.json({items:calendars});
    const match=u.pathname.match(/\/calendars\/([^/]+)\/events(?:\/([^/]+))?$/),calendar=decodeURIComponent(match[1]),id=match[2];
    if(options.method==='POST'){
      const body=JSON.parse(options.body);writes.push(body);if(flags.writeFailure){flags.writeFailure=false;throw new TypeError('Synthetic offline');}
      rows[calendar].push({...body,status:'confirmed'});return Response.json({...body,status:'confirmed'});
    }
    if(id){const found=rows[calendar].find(e=>e.id===id);return Response.json(found||{error:{message:'Not found'}},{status:found?200:404});}
    assert.equal(u.searchParams.get('timeMin'),'2026-10-12T22:00:00.000Z');assert.equal(u.searchParams.get('timeMax'),'2026-10-13T10:00:00.000Z');
    if(flags.readFailure&&calendar==='other@test.example')return Response.json({error:{message:'Synthetic failure'}},{status:503});
    return Response.json({items:rows[calendar]});
  }});
  vm.runInContext(source+'\nglobalThis.actions={connect,sync,openGap,saveGap,checkSave,state:()=>({pending,ready,saving,selected})};',context);
  return {el,actions:context.actions,flags,writes,requests};
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
