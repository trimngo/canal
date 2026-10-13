const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#f4f6fc"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-title" content="Notify Test"><meta name="description" content="A simple test of PWA notifications on your phone."><link rel="manifest" href="/manifest.webmanifest"><link rel="icon" href="/icon.svg"><link rel="apple-touch-icon" href="/icon.png"><title>Time Ledger · Notification test</title><style>
:root{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#1b2540;background:#f4f6fc}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;padding:26px 20px calc(28px + env(safe-area-inset-bottom))}main{max-width:440px;margin:0 auto}.brand{display:flex;align-items:center;gap:9px;font-size:13px;font-weight:650;color:#6f7b97;margin-bottom:36px}.brand span{display:grid;place-items:center;width:30px;height:30px;border-radius:10px;background:#315eec;color:white;font-size:19px}.eyebrow{font-size:10px;letter-spacing:1.5px;font-weight:650;color:#7583a3}h1{font-size:37px;line-height:1.12;letter-spacing:-1.4px;margin:12px 0 14px}h1 span{color:#315eec}.intro{font-size:14px;line-height:1.7;color:#73809a;margin:0 0 25px}.card{background:white;border:1px solid #e3e8f3;border-radius:18px;padding:20px;margin:12px 0}.step{display:flex;align-items:center;gap:10px;margin-bottom:10px}.number{display:grid;place-items:center;width:24px;height:24px;background:#eef3ff;border-radius:8px;color:#315eec;font-size:11px;font-weight:700}h2{font-size:16px;letter-spacing:-.3px;margin:0}.card p{font-size:12px;color:#74809a;line-height:1.65;margin:9px 0 14px}button,a.button{width:100%;min-height:48px;border:0;border-radius:11px;background:#315eec;color:white;font:600 13px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;padding:13px 14px;cursor:pointer;display:block;text-align:center;text-decoration:none}button:disabled{opacity:.45;cursor:default}.secondary{background:#edf2ff;color:#315eec;margin-top:9px}button:focus-visible,a:focus-visible{outline:3px solid #a3baff;outline-offset:3px}.hint{padding:15px 16px;background:#eaf0ff;border:1px solid #dbe5ff;border-radius:13px;font-size:12px;line-height:1.7;color:#5872a5}.hint strong{color:#254bba}.hint ol{margin:8px 0 0;padding-left:18px}.hint[hidden]{display:none}.status{display:flex;justify-content:space-between;gap:12px;padding:10px 0;border-bottom:1px solid #edf0f6;font-size:11px}.status:last-child{border:0}.status span{color:#8490a9}.status strong{font-size:11px;font-weight:550;text-align:right;max-width:65%;overflow-wrap:anywhere}.message{font-size:12px;line-height:1.7;padding:13px 15px;border-radius:12px;background:#eaf0ff;color:#38538c;white-space:pre-line;margin:14px 0}.message.error{background:#fff0eb;color:#a34d32}.message[hidden]{display:none}.quiet{font-size:10px;line-height:1.8;text-align:center;color:#8b96ab;margin:18px 0}.badge{display:inline-block;background:#e9f7f1;color:#2c9676;padding:3px 7px;border-radius:5px;font-size:10px;font-weight:600;margin-left:auto}.reset{background:none;color:#8490a9;font-size:10px;min-height:30px;padding:3px;margin-top:10px}.small{font-size:10px;color:#8a94aa}.dismiss{margin-top:10px;background:#edf2ff;color:#315eec}.loading{font-size:12px;color:#7b88a3}footer{padding-top:10px;text-align:center;font-size:10px;color:#96a0b4}@media(min-width:650px){body{padding-top:50px}main{max-width:440px}}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
</style></head><body><main><div class="brand"><span>↗</span>Time Ledger / notification test</div><div class="eyebrow">LET’S CHECK THE BASICS</div><h1>Can your phone<br><span>get the message?</span></h1><p class="intro">A small test before we build the rest. Allow notifications, then send yourself a real push.</p>
<div id="install-hint" class="hint" hidden><strong>First, install this on your iPhone.</strong><ol><li>Open this link in Safari and sign in if asked.</li><li>Tap Share, then <b>Add to Home Screen</b>.</li><li>Open <b>Notify Test</b> from your Home Screen.</li></ol></div>
<section class="card"><div class="step"><span class="number">1</span><h2>Allow notifications</h2><span id="enabled-badge" class="badge" hidden>Ready</span></div><p>Google Calendar access isn’t needed for this test. Your iPhone will ask you to allow alerts.</p><button id="enable" disabled>Getting ready…</button><div id="blocked-hint" class="small" hidden>Notifications are blocked. Open iPhone Settings → Notifications → Notify Test and enable Allow Notifications, then reopen the app.</div></section>
<section class="card"><div class="step"><span class="number">2</span><h2>Send a test</h2></div><p><b>Send now</b> checks delivery. For the background test, tap the second button and immediately lock your phone. The server sends a push after 15 seconds.</p><button id="send-now" disabled>Send test now</button><button id="send-later" class="secondary" disabled>Send in 15 seconds · lock phone</button></section>
<div id="message" class="message" role="status" aria-live="polite" hidden></div>
<section class="card"><div class="step"><h2>Connection check</h2></div><div class="status"><span>Installed app</span><strong id="installed-status">Checking…</strong></div><div class="status"><span>Permission</span><strong id="permission-status">Checking…</strong></div><div class="status"><span>Push subscription</span><strong id="subscription-status">Not enabled</strong></div><div class="status"><span>Last server result</span><strong id="server-status">No test sent</strong></div><button id="reset" class="reset" disabled>Reset push subscription</button></section>
<p class="quiet">If nothing appears, check Notification Center and your Focus settings. A server-accepted push does not confirm that your phone displayed it.</p><footer>Calendar work is paused. This page only tests notifications.</footer></main><script src="/client.js" defer></script></body></html>`;

const client = `(() => {
 const $=id=>document.getElementById(id);
 const installed=()=>matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 const ios=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
 let reg=null,subscription=null,publicKey=null,busy=false;
 const message=(text,error=false)=>{$('message').textContent=text;$('message').hidden=false;$('message').classList.toggle('error',error);};
 const bytes=str=>Uint8Array.from(atob(str.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(str.length/4)*4,'=')),c=>c.charCodeAt(0));
 function state(){
   const permission='Notification' in window?Notification.permission:'unsupported';
   $('installed-status').textContent=installed()?'Yes':ios?'Add to Home Screen':'Browser tab';
   $('permission-status').textContent=permission;
   $('subscription-status').textContent=subscription?'Enabled':'Not enabled';
   $('enabled-badge').hidden=!subscription;
   $('blocked-hint').hidden=permission!=='denied';
   const available=reg&&publicKey&&'PushManager' in window&&'Notification' in window&&(!ios||installed());
   $('enable').disabled=busy||!available;
   $('enable').textContent=subscription?'Notifications enabled':permission==='denied'?'Permission blocked':ios&&!installed()?'Install from Safari first':'Enable notifications';
   if(permission==='denied')$('enable').disabled=true;
   $('send-now').disabled=busy||!subscription;
   $('send-later').disabled=busy||!subscription;
   $('reset').disabled=busy||!subscription;
 }
 async function json(url,options){
   let response;try{response=await fetch(url,{cache:'no-store',credentials:'same-origin',...options});}catch{throw new Error('Could not reach the server. Check your connection and try again.');}
   let result;try{result=await response.json();}catch{throw new Error('The server returned a sign-in page or an unreadable response. Sign in in Safari and reopen this app.');}
   if(!response.ok)throw new Error(result.error||'The request failed.');return result;
 }
 async function initialize(){
   $('install-hint').hidden=!ios||installed();
   if(!isSecureContext){message('This test needs an HTTPS address.',true);state();return;}
   if(!('serviceWorker' in navigator)||!('Notification' in window)||!('PushManager' in window)){
     message(ios&&!installed()?'Add this page to your Home Screen, then open it there to enable notifications.':'This browser does not support Web Push. Try Safari on an installed iPhone app, or Chrome on desktop.',true);state();return;
   }
   try{await navigator.serviceWorker.register('/sw.js',{scope:'/'});reg=await navigator.serviceWorker.ready;const config=await json('/api/config');publicKey=config.publicKey;
     subscription=await reg.pushManager.getSubscription();
     if(subscription){const old=new Uint8Array(subscription.options.applicationServerKey||[]),fresh=bytes(publicKey);if(old.length!==fresh.length||old.some((x,i)=>x!==fresh[i])){await subscription.unsubscribe();subscription=null;}}
     if(new URLSearchParams(location.search).has('openedFromNotification'))message('You opened the app from a notification. Delivery worked.');
   }catch(e){message(e.message,true);}
   state();
 }
 $('enable').onclick=async()=>{
   if(busy||!reg||!publicKey)return;
   busy=true;state();
   try{const permission=await Notification.requestPermission();if(permission!=='granted'){message('Notifications were not enabled. You can change this in your phone’s notification settings.',true);return;}
     subscription=await reg.pushManager.getSubscription()||await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes(publicKey)});
     message('Notifications enabled. Try “Send test now,” then test with your phone locked.');
   }catch(e){message('Could not enable push: '+e.message,true);}finally{busy=false;state();}
 };
 async function send(delay){
   if(busy||!subscription)return;busy=true;state();$('server-status').textContent='Sending…';
   try{const result=await json('/api/test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({endpoint:subscription.endpoint,delay})});
     if(result.queued){$('server-status').textContent='Queued for 15 seconds';message('Test queued. Lock your phone now. The server will send after 15 seconds. Check the Lock Screen or Notification Center.');}
     else{$('server-status').textContent='Push service accepted';message('The push service accepted your test. Look for “Time’s up — notification test” on your phone.');}
   }catch(e){$('server-status').textContent='Test failed';message(e.message,true);}finally{busy=false;state();}
 }
 $('send-now').onclick=()=>send(0);$('send-later').onclick=()=>send(15);
 $('reset').onclick=async()=>{if(!subscription||busy)return;busy=true;state();try{if(await subscription.unsubscribe()){subscription=null;message('Subscription reset. Tap Enable notifications to subscribe again.');}else throw new Error('Reset was not confirmed.');}catch(e){message(e.message,true);}finally{busy=false;state();}};
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)state();});
 initialize();
})();`;

const sw = `self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 event.waitUntil(self.registration.showNotification('Time’s up — notification test',{
   body:'Your PWA received a real push. Tap to return to the test.',
   icon:'/icon.png',badge:'/icon.png',tag:'push-test-'+Date.now(),data:{url:'/?openedFromNotification=1'}
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
 const match=windows.find(client=>new URL(client.url).origin===self.location.origin);
 if(match){await match.navigate('/?openedFromNotification=1');return match.focus();}
 return self.clients.openWindow('/?openedFromNotification=1');})());
});`;

const icon = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 192 192"><rect width="192" height="192" rx="48" fill="#315eec"/><path d="M55 137 137 55M68 55h69v69" fill="none" stroke="#fff" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/></svg>';
// Replaced by scripts/make-icon.mjs with a self-contained PNG before packaging.
const ICON_PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAAAFR0lEQVR4nO3aS5IcNxAE0b7SXIj3X/AOI9NCMkrzq6wKIJAZXmZvywHQ4Tu+3n79fpm9I5p1f4wcJ2sbgPvhMNPxAbgfCBmOC8D9IMhkD8D9AMC7KwD3pYE/bQ3AfVngM8sDcF8QuGJJAO5LARXSANyXAe6QBOC+BPAEASDaowDchwcUbgXgPjSgVArAfVhgBQJAtEsBuA8JrEQAiPZtAO7DATsQAKJ9GoD7UMBOBIBoBIBoBIBo/wnAfRjAgQAQjQAQjQAQjQAQjQAQjQAQ7cX4EY0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0AEI0Afv1+56t97t+LABi//XP/bgTA+O2f+/cjAAKwfu7fjwAIwPq5fz8CIADr5/79CIAArJ/79yMAArB+7t+PAAjA+rl/PwIgAuvn/u0IgAisn/t3IwCUEMBHBBBixee+kwIBBFj1ue+lQADDrfzcd1MggMFWf+77KRDAUDs+9x0VCGCgXZ/7ngoEMMzOz31XBQIYZPfnvq8CAQyhGjQBoB3V+Kv/lvveCgTQnHL81X/PfXcFAmhMPf7qv+m+vwIBNLVi/NV/1/0GCgTQ0KrxV/9t9zsoEEAzK8df/ffdb6FAAI2sHn/1b7jfQ4EAmtgx/urfcb+JAgE0sGv81b/lfhcFAjjczvFX/577bRQI4GC7x1/9m+73USCAQznGX/277jdSIIADucZf/dvud1IggMM4x1/9++63UiCAg7jHXz2D+70UCOAQJ4y/eg73mykQwAFOGX/1LO53UyAAs5PGXz2P++0UCMDotPFXz+R+PwUCMDlx/NVzud9QgQAMTh1/9Wzud1QggM1OHn/1fO63VCCAjU4ff/WM7vdUIIBNOoy/ek73myoQwAZdxl89q/tdFQhgsU7jr57X/bYKBLBQt/FXz+x+XwUCWKTj+Kvndr+xAgEs0HX81bO731mBAMQ6j796fvdbKxCAUPfxV+/gPqsCAYhMGH/1Hu6zKhDA5tGcPqaOZ36CADYOpsOQup77LgLYNJYuI+p89jsIYMNQOg2o+/mrCGDxSLqNZ8IdKghg4UA6DmfKPa4igEXj6DqaSXe5ggAWDKPzYKbd5ycEIB5F97FMvNN3CEA4iAlDmXqvrxCAaAxTRjL5bp8hAMEQJg1k+v3+jwAejmDaOBLu+CcCeDCAicNIuec/CODmjz91FEl3fSOAez/85EGk3ZcAGP/tt3CfVSE+AMZ//z3cZ1WIDoDxP3sT91kVYgNg/M/fxX1WhcgAGL/mbdxnVYgLgPHr3sd9VoWoABi/9o3cZ1WICYDx69/JfVaFiAAY/5q3cp9VYXwAjH/Nm7nPqDI6AMa/5u3cZ1MaGwDjxxUjA2D8uGpcAIwfFaMCYPyoGhMA48cdBMD4oxEA448WH4D73PCKDsB9ZvjFBuA+L84QGYD7rDjHmADewv4TFzRGBfAW9J+4oDEuAKCCABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABCNABDt7wCIAKleBIBkBIBoBIBoBIBoBIBoBIBo/wZABEjzIgAkIwBEIwBE+xAAESDFiwCQ7MsAiADTvQgAyX4MgAgw1YetEwCSXA6ACDDNpzv/LgAiwBRfbvynAIgA3X27bwLAdI8DIAJ09eO2rwZABOjm0q4rARABuri86WoAhICTlbd8NwAiwGlu7fhJAESAU9ze8NMACAFOj7erCoAQsJNss+oACAErybe6KgCCgMLybe4KgDhgG/l3/gLBcRclBa579AAAAABJRU5ErkJggg==';
const manifest={id:'/notification-test',name:'Time Ledger Notification Test',short_name:'Notify Test',start_url:'/',scope:'/',display:'standalone',background_color:'#f4f6fc',theme_color:'#f4f6fc',icons:[{src:'/icon.png',sizes:'192x192',type:'image/png',purpose:'any'}]};
const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'strict-origin-when-cross-origin'};
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...headers,'Content-Type':'application/json; charset=utf-8'}});
function b64url(value){const bytes=typeof value==='string'?new TextEncoder().encode(value):new Uint8Array(value);let str='';for(const b of bytes)str+=String.fromCharCode(b);return btoa(str).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/g,'');}
export function validateEndpoint(endpoint){
 if(typeof endpoint!=='string'||endpoint.length>4096)throw new Error('Invalid push subscription.');
 let url;try{url=new URL(endpoint);}catch{throw new Error('Invalid push subscription.');}
 const apple=url.hostname==='web.push.apple.com'||url.hostname.endsWith('.push.apple.com');
 const google=url.hostname==='fcm.googleapis.com';
 const mozilla=url.hostname==='updates.push.services.mozilla.com';
 if(url.protocol!=='https:'||url.username||url.password||url.hash||(url.port&&url.port!=='443')||!(apple||google||mozilla))throw new Error('Unsupported push service. This test supports iPhone Safari, Chrome, and Firefox.');
 return url;
}
export async function sendPush(endpoint,env){
 const url=validateEndpoint(endpoint);
 const key=await crypto.subtle.importKey('jwk',JSON.parse(env.VAPID_PRIVATE_KEY_JWK),{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
 const unsigned=b64url(JSON.stringify({typ:'JWT',alg:'ES256'}))+'.'+b64url(JSON.stringify({aud:url.origin,exp:Math.floor(Date.now()/1000)+3600,sub:env.VAPID_SUBJECT}));
 const signature=await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,new TextEncoder().encode(unsigned));
 // An empty Web Push wakes the service worker, which always shows a visible notification.
 const response=await fetch(url.href,{method:'POST',headers:{Authorization:'vapid t='+unsigned+'.'+b64url(signature)+', k='+env.VAPID_PUBLIC_KEY,TTL:'300',Urgency:'high'},body:new Uint8Array(0),redirect:'error',signal:AbortSignal.timeout(8000)});
 if(response.status===404||response.status===410)throw new Error('This subscription expired. Reset it and enable notifications again.');
 if(response.status!==201&&response.status!==202)throw new Error('The push service rejected the test (HTTP '+response.status+').');
 return response.status;
}
export default {
 async fetch(request,env,ctx){
  const url=new URL(request.url);
  if(request.method==='GET'){
   if(url.pathname==='/')return new Response(page,{headers:{...headers,'Content-Type':'text/html; charset=utf-8'}});
   if(url.pathname==='/client.js')return new Response(client,{headers:{...headers,'Content-Type':'application/javascript; charset=utf-8'}});
   if(url.pathname==='/sw.js')return new Response(sw,{headers:{...headers,'Content-Type':'application/javascript; charset=utf-8','Service-Worker-Allowed':'/'}});
   if(url.pathname==='/icon.svg')return new Response(icon,{headers:{...headers,'Content-Type':'image/svg+xml'}});
   if(url.pathname==='/icon.png')return new Response(Uint8Array.from(atob(ICON_PNG_BASE64),c=>c.charCodeAt(0)),{headers:{...headers,'Content-Type':'image/png'}});
   if(url.pathname==='/manifest.webmanifest')return new Response(JSON.stringify(manifest),{headers:{...headers,'Content-Type':'application/manifest+json'}});
   if(url.pathname==='/api/config')return env.VAPID_PUBLIC_KEY&&env.VAPID_PRIVATE_KEY_JWK?json({publicKey:env.VAPID_PUBLIC_KEY}):json({error:'The push sender is not configured yet.'},503);
   return new Response('Not found',{status:404});
  }
  if(request.method!=='POST'||url.pathname!=='/api/test')return new Response('Not found',{status:404});
  if(!request.headers.get('oai-authenticated-user-id'))return json({error:'Sign in to this private app in Safari, then reopen it from your Home Screen.'},401);
  if(request.headers.get('Origin')!==url.origin)return json({error:'Open the test from its own app address.'},403);
  if(!request.headers.get('Content-Type')?.startsWith('application/json'))return json({error:'Expected a JSON request.'},415);
  if(!env.VAPID_PUBLIC_KEY||!env.VAPID_PRIVATE_KEY_JWK||!env.VAPID_SUBJECT)return json({error:'The push sender is not configured yet.'},503);
  let data;
  try{const body=await request.text();if(body.length>8192)return json({error:'Request too large.'},413);data=JSON.parse(body);validateEndpoint(data.endpoint);if(![0,15].includes(data.delay))throw new Error('Choose an immediate or 15-second test.');}
  catch(e){return json({error:e.message||'Invalid request.'},400);}
  if(data.delay===15){
   const id=crypto.randomUUID();
   ctx.waitUntil((async()=>{await new Promise(resolve=>setTimeout(resolve,15000));const status=await sendPush(data.endpoint,env);console.log(JSON.stringify({test:id,outcome:'accepted',providerStatus:status}));})().catch(()=>console.error(JSON.stringify({test:id,outcome:'failed'}))));
   return json({queued:true,delay:15,testId:id},202);
  }
  try{return json({accepted:true,providerStatus:await sendPush(data.endpoint,env)});}catch(e){return json({error:e.message||'The push request failed.'},502);}
 }
};
