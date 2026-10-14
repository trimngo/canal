import test from 'node:test';
import assert from 'node:assert/strict';
import worker,{validateEndpoint,sendPush} from '../worker/index.js';
const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const env={VAPID_PRIVATE_KEY_JWK:JSON.stringify(await crypto.subtle.exportKey('jwk',pair.privateKey)),VAPID_PUBLIC_KEY:Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64url'),VAPID_SUBJECT:'https://test.example'};
const endpoint='https://web.push.apple.com/fixture-not-a-real-subscription';
function request(data,extra={}){return new Request('https://test.example/api/test',{method:'POST',headers:{'Origin':'https://test.example','Content-Type':'application/json','oai-authenticated-user-id':'fixture',...extra},body:JSON.stringify(data)});}
test('PWA assets, manifest, PNG, and service worker are valid',async()=>{
 const page=await worker.fetch(new Request('https://test.example/'),env,{});assert.equal(page.status,200);assert.match(await page.text(),/What were you doing/);
 const notifications=await worker.fetch(new Request('https://test.example/notifications'),env,{});assert.match(await notifications.text(),/Send in 15 seconds/);
 const manifest=await (await worker.fetch(new Request('https://test.example/manifest.webmanifest'),env,{})).json();assert.equal(manifest.display,'standalone');assert.equal(manifest.start_url,'/');
 const icon=await worker.fetch(new Request('https://test.example/icon.png'),env,{});assert.deepEqual([...new Uint8Array(await icon.arrayBuffer()).slice(0,8)],[137,80,78,71,13,10,26,10]);
 const sw=await worker.fetch(new Request('https://test.example/sw.js'),env,{});assert.equal(sw.headers.get('Service-Worker-Allowed'),'/');const swText=await sw.text();new Function(swText);assert.match(swText,/showNotification/);
 const client=await worker.fetch(new Request('https://test.example/client.js'),env,{});new Function(await client.text());
 const config=await (await worker.fetch(new Request('https://test.example/api/config'),env,{})).json();assert.deepEqual(Object.keys(config),['publicKey']);
});
test('push endpoint allowlist prevents arbitrary outbound requests',()=>{
 for(const url of ['http://web.push.apple.com/x','https://localhost/x','https://web.push.apple.com.attacker.example/x','https://fcm.googleapis.com:1234/x','https://user:password@web.push.apple.com/x'])assert.throws(()=>validateEndpoint(url));
 assert.equal(validateEndpoint(endpoint).hostname,'web.push.apple.com');assert.ok(validateEndpoint('https://fcm.googleapis.com/fcm/send/fixture'));
});
test('sender signs correct VAPID JWT, uses empty push, and reports only acceptance',async()=>{
 const original=globalThis.fetch;try{globalThis.fetch=async(url,options)=>{
  assert.equal(url,endpoint);assert.equal(options.method,'POST');assert.equal(options.body.length,0);assert.equal(options.redirect,'manual');assert.equal(options.headers.TTL,'300');
  const jwt=options.headers.Authorization.match(/vapid t=([^,]+), k=/)[1],parts=jwt.split('.');
  const payload=JSON.parse(Buffer.from(parts[1],'base64url'));assert.equal(payload.aud,'https://web.push.apple.com');assert.equal(payload.sub,'https://test.example');
  assert.ok(payload.exp>Date.now()/1000&&payload.exp<Date.now()/1000+86400);
  assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},pair.publicKey,Buffer.from(parts[2],'base64url'),new TextEncoder().encode(parts[0]+'.'+parts[1])),true);
  return new Response(null,{status:201});};assert.equal(await sendPush(endpoint,env),201);
 }finally{globalThis.fetch=original;}
});
test('requests require signed-in identity, same origin, and bounded delay',async()=>{
 const anonymous=request({endpoint,delay:0});anonymous.headers.delete('oai-authenticated-user-id');assert.equal((await worker.fetch(anonymous,env,{})).status,401);
 assert.equal((await worker.fetch(request({endpoint,delay:0},{Origin:'https://other.example'}),env,{})).status,403);
 assert.equal((await worker.fetch(request({endpoint,delay:600}),env,{})).status,400);
 assert.equal((await worker.fetch(request({endpoint:'https://localhost/x',delay:0}),env,{})).status,400);
});
test('immediate test performs one push and does not claim device delivery',async()=>{
 const original=globalThis.fetch;let calls=0;try{globalThis.fetch=async()=>{calls++;return new Response(null,{status:201});};const response=await worker.fetch(request({endpoint,delay:0}),env,{});assert.equal(response.status,200);const data=await response.json();assert.equal(data.accepted,true);assert.equal(data.delivered,undefined);assert.equal(calls,1);}finally{globalThis.fetch=original;}
});
test('delayed test queues a bounded server task after the response',async()=>{
 const fetchOriginal=globalThis.fetch,timerOriginal=globalThis.setTimeout;const tasks=[];let delay,calls=0;
 try{globalThis.setTimeout=(fn,ms)=>{delay=ms;return timerOriginal(fn,0);};globalThis.fetch=async()=>{calls++;return new Response(null,{status:201});};
 const response=await worker.fetch(request({endpoint,delay:15}),env,{waitUntil:p=>tasks.push(p)});assert.equal(response.status,202);assert.equal((await response.json()).queued,true);assert.equal(calls,0);assert.equal(delay,15000);await Promise.all(tasks);assert.equal(calls,1);
 }finally{globalThis.fetch=fetchOriginal;globalThis.setTimeout=timerOriginal;}
});
test('expired subscriptions and provider failures are actionable',async()=>{
 const original=globalThis.fetch;try{globalThis.fetch=async()=>new Response(null,{status:410});const response=await worker.fetch(request({endpoint,delay:0}),env,{});assert.equal(response.status,502);assert.match((await response.json()).error,/expired/);globalThis.fetch=async()=>new Response(null,{status:500});await assert.rejects(()=>sendPush(endpoint,env),/500/);}finally{globalThis.fetch=original;}
});
test('edge-compatible manual redirects never forward push credentials',async()=>{
 const original=globalThis.fetch;let calls=0;
 try{globalThis.fetch=async(url,options)=>{
  calls++;if(options.redirect==='error')throw new TypeError('Invalid redirect value');
  assert.equal(options.redirect,'manual');
  return new Response(null,{status:302,headers:{Location:'https://unrelated.example/push'}});
 };
 const response=await worker.fetch(request({endpoint,delay:0}),env,{});
 assert.equal(response.status,502);assert.match((await response.json()).error,/redirected/);assert.equal(calls,1);
 }finally{globalThis.fetch=original;}
});
