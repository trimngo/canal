import test from 'node:test';
import assert from 'node:assert/strict';
import {CategoryJournal,categoryPlan,categoryState,categoryPatch} from '../web/categories.mjs';
const event=()=>({id:'occurrence',etag:'"v1"',summary:'Reading',description:'Original\nnotes',start:{dateTime:'2026-10-13T08:00Z'},extendedProperties:{private:{other:'keep'}}});
const category={id:'reading',name:'Reading'};
function storage(){const rows=new Map();return {getItem:k=>rows.get(k)||null,setItem:(k,v)=>rows.set(k,v)};}
test('a missing backup prevents any outbound calendar edit',async()=>{
  const original=globalThis.fetch;let calls=0;
  try{globalThis.fetch=async()=>{calls++;return Response.json({});};const journal=new CategoryJournal({getItem(){return null;},setItem(){throw new Error('No storage');}},'test');
  await assert.rejects(()=>journal.apply('synthetic',[categoryPlan(event(),'primary',category)]),/Undo backup/);assert.equal(calls,0);
  }finally{globalThis.fetch=original;}
});
test('lost category responses preserve the original snapshot and are recovered by reading instead of replaying',async()=>{
  const original=globalThis.fetch,raw=event(),plan=categoryPlan(raw,'primary',category),journal=new CategoryJournal(storage(),'test');let patches=0,reads=0;
  try{globalThis.fetch=async(url,options)=>{
    if(options.method==='PATCH'){patches++;const patch=categoryPatch(plan.after);raw.description=patch.description;raw.extendedProperties.private={...plan.after.private};raw.etag='"v2"';throw new TypeError('Response lost');}
    reads++;return Response.json(raw);
  };await assert.rejects(()=>journal.apply('synthetic',[plan]),/Stopped after/);assert.equal(journal.unresolved(),true);assert.equal(journal.read()[0].items[0].before.description,'Original\nnotes');
  await journal.recover('synthetic');assert.equal(patches,1);assert.equal(reads,1);assert.equal(journal.unresolved(),false);assert.equal(journal.read()[0].items[0].status,'applied');
  }finally{globalThis.fetch=original;}
});
test('a changed event stops the remaining batch and keeps already-applied events reversible',async()=>{
  const original=globalThis.fetch,one=categoryPlan(event(),'primary',category),two=categoryPlan({...event(),id:'second'},'primary',category),three=categoryPlan({...event(),id:'third'},'primary',category),journal=new CategoryJournal(storage(),'test');let calls=0;
  try{globalThis.fetch=async(url,options)=>{
    calls++;if(calls===2)return Response.json({error:{message:'Changed'}},{status:412});
    return Response.json({...event(),description:one.after.description,extendedProperties:{private:one.after.private},etag:'"v2"'});
  };await assert.rejects(()=>journal.apply('synthetic',[one,two,three]),/1 of 3/);assert.equal(calls,2);assert.deepEqual(journal.read()[0].items.map(i=>i.status),['applied','failed','skipped']);
  }finally{globalThis.fetch=original;}
});
test('existing notes and foreign metadata survive retagging; edited managed notes and recurring masters are protected',()=>{
  const raw=event(),plan=categoryPlan(raw,'primary',category);
  const tagged={...raw,description:plan.after.description,extendedProperties:{private:plan.after.private}};
  const renamed=categoryPlan(tagged,'primary',{...category,name:'Learning'});assert.equal(renamed.after.description,'Original\nnotes\n\nTime Ledger category: Learning');assert.equal(renamed.after.private.other,'keep');
  const cleared=categoryPlan(tagged,'primary',null);assert.deepEqual(cleared.after,categoryState(raw));
  assert.throws(()=>categoryPlan({...tagged,description:'User moved the category note'},'primary',category),/edited or moved/);
  assert.throws(()=>categoryPlan({...raw,recurrence:['RRULE:FREQ=DAILY']},'primary',category),/recurring series/);
});
