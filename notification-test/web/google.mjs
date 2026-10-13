export const READ_SCOPES='https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events.readonly';
export const WRITE_SCOPE='https://www.googleapis.com/auth/calendar.events';
export class CalendarError extends Error{
  constructor(message,status=0,uncertain=false){super(message);this.status=status;this.uncertain=uncertain;}
}
export async function calendarRequest(token,path,{method='GET',body,signal,ifMatch}={}){
  if(!token)throw new CalendarError('Connect Google Calendar first.',401);
  let response;
  const mutation=method==='POST'||method==='DELETE';
  try{response=await fetch('https://www.googleapis.com/calendar/v3/'+path,{method,headers:{Authorization:`Bearer ${token}`,...(body?{'Content-Type':'application/json'}:{}),...(ifMatch?{'If-Match':ifMatch}:{})},...(body?{body:JSON.stringify(body)}:{}),signal,cache:'no-store'});}
  catch{throw new CalendarError(method==='DELETE'?'We could not confirm whether Google deleted this event. Check its status before trying again.':method==='POST'?'We could not confirm whether Google saved this block. Check its status before trying again.':'Could not reach Google Calendar. Check your connection and refresh.',0,mutation);}
  if(method==='DELETE'&&response.status===204)return null;
  let data;
  try{data=await response.json();}catch{throw new CalendarError('Google returned an unreadable response.',response.status,mutation);}
  if(!response.ok){
    const message=response.status===401?'Your Google session expired. Reconnect to continue.':response.status===403?'Google denied access. Check that Calendar API is enabled and that you granted the requested permissions.':response.status===412?'This event changed in Google Calendar. Refresh and review it before deleting.':response.status===429?'Google is temporarily limiting requests. Wait a moment before refreshing.':data.error?.message||'Google Calendar could not complete the request.';
    throw new CalendarError(message,response.status,mutation&&response.status>=500);
  }
  return data;
}
export async function listCalendars(token){
  let pageToken,result=[];
  for(let page=0;page<20;page++){
    const query=new URLSearchParams({maxResults:'250',showHidden:'false'});if(pageToken)query.set('pageToken',pageToken);
    const data=await calendarRequest(token,'users/me/calendarList?'+query);
    result.push(...(data.items||[]).filter(c=>!c.deleted));pageToken=data.nextPageToken;
    if(!pageToken)return result;
  }
  throw new CalendarError('There are too many calendars to load in one request.');
}
export async function listEvents(token,calendarId,start,end,signal){
  let pageToken,result=[];
  for(let page=0;page<20;page++){
    const query=new URLSearchParams({timeMin:new Date(start).toISOString(),timeMax:new Date(end).toISOString(),singleEvents:'true',showDeleted:'false',orderBy:'startTime',maxResults:'2500'});
    if(pageToken)query.set('pageToken',pageToken);
    const data=await calendarRequest(token,`calendars/${encodeURIComponent(calendarId)}/events?${query}`,{signal});
    result.push(...(data.items||[]));pageToken=data.nextPageToken;
    if(!pageToken)return result;
  }
  throw new CalendarError('This calendar has too many events to load completely. Select fewer calendars.');
}
export const eventPath=(calendarId,id)=>`calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(id)}`;
export async function createEvent(token,calendarId,draft){
  const event=await calendarRequest(token,`calendars/${encodeURIComponent(calendarId)}/events`,{method:'POST',body:draft});
  if(!event.id||event.status==='cancelled')throw new CalendarError('Google did not confirm a saved event.',0,true);
  return event;
}
export async function deleteEvent(token,calendarId,id,etag){
  const result=await calendarRequest(token,eventPath(calendarId,id)+'?sendUpdates=none',{method:'DELETE',ifMatch:etag});
  if(result!==null)throw new CalendarError('Google did not confirm deletion. Check its status before trying again.',0,true);
}
