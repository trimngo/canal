import {deflateSync} from 'node:zlib';
import {readFile,writeFile} from 'node:fs/promises';
const size=192,raw=Buffer.alloc((size*4+1)*size);
function distance(x,y,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)));return Math.hypot(x-a[0]-t*dx,y-a[1]-t*dy);}
for(let y=0;y<size;y++)for(let x=0;x<size;x++){
 const offset=y*(size*4+1)+1+x*4;
 const roundX=x<32?32:x>=160?159:x,roundY=y<32?32:y>=160?159:y;
 const visible=Math.hypot(x-roundX,y-roundY)<=32;
 const arrow=distance(x,y,[55,137],[137,55])<6||distance(x,y,[68,55],[137,55])<6||distance(x,y,[137,55],[137,124])<6;
 const color=arrow?[255,255,255]:[49,94,236];raw.set([...color,visible?255:0],offset);
}
function crc32(b){let c=0xffffffff;for(const v of b){c^=v;for(let i=0;i<8;i++)c=c&1?0xedb88320^(c>>>1):c>>>1;}return (c^0xffffffff)>>>0;}
function chunk(name,data){const type=Buffer.from(name),length=Buffer.alloc(4),crc=Buffer.alloc(4);length.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([type,data])));return Buffer.concat([length,type,data,crc]);}
const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(size,0);ihdr.writeUInt32BE(size,4);ihdr[8]=8;ihdr[9]=6;
const png=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
let source=await readFile('worker/index.js','utf8');source=source.replace(/const ICON_PNG_BASE64 = '[^']*';/,"const ICON_PNG_BASE64 = '"+png.toString('base64')+"';");await writeFile('worker/index.js',source);
console.log('Embedded 192px PWA icon.');
