import {calendarRequest,eventPath,listTaggedEvents,CalendarError} from './google.mjs';
export const CATEGORY_KEYS=['timeLedgerCategoryId','timeLedgerCategoryName','timeLedgerCategoryLine'];
export function categoryName(value){
  const name=value?.trim();
  if(!name||name.length>40||/[<>\r\n]/.test(name))throw new Error('Use a category name of 1–40 characters, without line breaks or < >.');
  return name;
}
export function categoryState(raw){return {description:raw.description||'',private:{...(raw.extendedProperties?.private||{})}};}
export function sameState(a,b){return a.description===b.description&&JSON.stringify(Object.entries(a.private).filter(([,v])=>v!==null).sort())===JSON.stringify(Object.entries(b.private).filter(([,v])=>v!==null).sort());}
export function categoryPlan(raw,calendarId,category){
  if(raw.recurrence)throw new Error('A recurring series cannot be edited here. Choose an individual occurrence.');
  if(!raw.etag||!raw.id||raw.status==='cancelled')throw new Error('This event cannot be safely edited. Refresh and try again.');
  const before=categoryState(raw),after=structuredClone(before),oldLine=before.private.timeLedgerCategoryLine;
  if(oldLine){
    if(after.description===oldLine)after.description='';
    else if(after.description.endsWith('\n\n'+oldLine))after.description=after.description.slice(0,-oldLine.length-2);
    else throw new Error('The saved category note was edited or moved in Google Calendar. No changes were made. Review that note in Google before changing its category here.');
  }
  for(const key of CATEGORY_KEYS)delete after.private[key];
  if(category){
    const name=categoryName(category.name),line='Time Ledger category: '+name;
    after.description+=(after.description?'\n\n':'')+line;
    Object.assign(after.private,{timeLedgerCategoryId:category.id,timeLedgerCategoryName:name,timeLedgerCategoryLine:line});
  }
  return {calendarId,id:raw.id,title:raw.summary||'Untitled event',when:raw.start?.dateTime||raw.start?.date||'',etag:raw.etag,before,after,status:'prepared'};
}
export function categoryPatch(state){
  const privateProps={...state.private};for(const key of CATEGORY_KEYS)if(!(key in privateProps))privateProps[key]=null;
  return {description:state.description,extendedProperties:{private:privateProps}};
}
export async function renamePlans(token,calendars,category,name,now,date){
  const plans=[];
  for(const calendar of calendars){
    const rows=await listTaggedEvents(token,calendar.id,category.id,now);
    for(const raw of rows){
      if(raw.extendedProperties?.private?.timeLedgerCategoryId!==category.id||raw.status==='cancelled')continue;
      if(raw.start?.dateTime?Date.parse(raw.start.dateTime)>=now:!raw.start?.date||raw.start.date>date)continue;
      if(!['owner','writer'].includes(calendar.accessRole))throw new Error('A tagged event is on a read-only calendar: '+calendar.summary+'. Rename was stopped before making any changes.');
      const plan=categoryPlan(raw,calendar.id,{...category,name});plan.calendarName=calendar.summary||calendar.id;if(!sameState(plan.before,plan.after))plans.push(plan);
      if(plans.length>100)throw new Error('This rename affects more than 100 events. No changes were made.');
    }
  }
  return plans;
}
export class CategoryJournal{
  constructor(storage,account){this.storage=storage;this.key='time-ledger:today:category-undo:'+account;}
  read(){
    let records;try{records=JSON.parse(this.storage.getItem(this.key)||'[]');}catch{throw new Error('The category Undo history could not be read. Calendar edits are blocked.');}
    if(!Array.isArray(records)||records.some(b=>!Array.isArray(b.items)))throw new Error('The category Undo history is invalid. Calendar edits are blocked.');
    return records;
  }
  write(records){
    const text=JSON.stringify(records);
    try{this.storage.setItem(this.key,text);if(this.storage.getItem(this.key)!==text)throw new Error();}
    catch{throw new Error('The Undo backup could not be saved on this device. Calendar edits are blocked.');}
  }
  unresolved(){return this.read().some(b=>b.items.some(i=>['prepared','uncertain','undoing'].includes(i.status)));}
  async apply(token,plans,meta={}){
    if(this.unresolved())throw new Error('Check the interrupted category change before making another edit.');
    const history=this.read(),batch={id:crypto.randomUUID(),created:Date.now(),meta,items:structuredClone(plans)};
    if(!plans.length)return {batch,changed:0};
    history.push(batch);this.write(history);let changed=0;
    for(const item of batch.items){
      let sent=false;
      try{
        const raw=await calendarRequest(token,eventPath(item.calendarId,item.id)+'?sendUpdates=none',{method:'PATCH',body:categoryPatch(item.after),ifMatch:item.etag});
        if(!raw.etag||!sameState(categoryState(raw),item.after))throw new CalendarError('The category update was not confirmed.',0,true);
        sent=true;item.status='applied';item.afterEtag=raw.etag;changed++;this.write(history);
      }catch(e){
        item.status=e.uncertain||sent?'uncertain':'failed';item.error=e.message;
        for(const remaining of batch.items)if(remaining!==item&&remaining.status==='prepared')remaining.status='skipped';
        this.write(history);throw new Error(`Stopped after ${changed} of ${plans.length} event updates. ${e.message} Use Check or Undo in Settings.`);
      }
    }
    return {batch,changed};
  }
  async recover(token){
    const history=this.read();let checked=0;
    for(const batch of history)for(const item of batch.items){
      if(!['prepared','uncertain','undoing'].includes(item.status))continue;
      const raw=await calendarRequest(token,eventPath(item.calendarId,item.id)),state=categoryState(raw);
      if(sameState(state,item.after)){item.status='applied';item.afterEtag=raw.etag;}
      else if(sameState(state,item.before))item.status='unchanged';
      else item.status='conflict';
      checked++;this.write(history);
    }
    return checked;
  }
  async undo(token){
    if(this.unresolved())throw new Error('Check the interrupted category change before using Undo.');
    const history=this.read(),batch=[...history].reverse().find(b=>b.items.some(i=>i.status==='applied'));
    if(!batch)throw new Error('There is no category edit to undo.');
    // Check every event first. A newer calendar edit prevents the whole Undo.
    const targets=[];
    for(const item of batch.items.filter(i=>i.status==='applied')){
      const raw=await calendarRequest(token,eventPath(item.calendarId,item.id));
      if(raw.etag!==item.afterEtag||!sameState(categoryState(raw),item.after))throw new Error('An event changed after categorization. Undo was stopped to protect the newer edit: '+item.title);
      targets.push({item,etag:raw.etag});
    }
    for(const {item,etag} of targets){
      item.status='undoing';this.write(history);
      let sent=false;
      try{
        const raw=await calendarRequest(token,eventPath(item.calendarId,item.id)+'?sendUpdates=none',{method:'PATCH',body:categoryPatch(item.before),ifMatch:etag});
        if(!raw.etag||!sameState(categoryState(raw),item.before))throw new CalendarError('Undo was not confirmed.',0,true);
        sent=true;item.status='undone';
        // Our own Undo can advance the version of an older backup in the same chain.
        for(const previous of history)for(const prior of previous.items){
          if(prior!==item&&prior.calendarId===item.calendarId&&prior.id===item.id&&prior.status==='applied'&&prior.afterEtag===item.etag&&sameState(prior.after,item.before))prior.afterEtag=raw.etag;
        }
        this.write(history);
      }catch(e){item.status=e.uncertain||sent?'undoing':'applied';this.write(history);throw new Error('Undo stopped. '+e.message);}
    }
    return batch;
  }
}
