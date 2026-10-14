self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('message',e=>{
 if(e.data?.type==='checkin-device'&&/^[0-9a-f]{64}$/.test(e.data.id))e.waitUntil((async()=>{const cache=await caches.open('time-ledger-push-device');await cache.put('/push-device',new Response(e.data.id));})());
});
self.addEventListener('push',e=>e.waitUntil((async()=>{
 let prompt={title:'What were you doing?',body:'Tap to record your last 15-minute period.',url:'/?checkin=1',slot:Math.floor(Date.now()/900000)*900000};
 try{
  const cache=await caches.open('time-ledger-push-device'),saved=await cache.match('/push-device'),device=saved?await saved.text():'';
  const response=await fetch('/api/checkins/prompt'+(device?'?device='+encodeURIComponent(device):''),{credentials:'include',cache:'no-store',signal:AbortSignal.timeout(5000)});
  if(response.ok){const data=await response.json();if(data.title&&data.url?.startsWith('/?slot=')&&Number.isSafeInteger(data.slot))prompt=data;}
 }catch{}
 await self.registration.showNotification(prompt.title,{body:prompt.body,icon:'/icon.png',badge:'/icon.png',tag:'time-checkin-'+prompt.slot,data:{url:prompt.url}});
})()));
self.addEventListener('notificationclick',e=>{
 e.notification.close();const target=e.notification.data?.url;
 const path=typeof target==='string'&&/^\/\?(slot=\d+|checkin=1)$/.test(target)?target:'/';
 e.waitUntil((async()=>{const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true}),found=windows.find(c=>new URL(c.url).origin===self.location.origin);if(found){await found.navigate(path);return found.focus();}return self.clients.openWindow(path);})());
});
