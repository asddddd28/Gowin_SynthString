// Compile the SynthUI palette/font/layout into deduplicated character rows.
// The hardware has no framebuffer and never uploads full-screen pixel images.
import fs from 'node:fs/promises';
import {FONT} from '../../../../SynthUI/src/pixel/font.mjs';
const root = new URL('../assets/', import.meta.url);
await fs.mkdir(root,{recursive:true});
const names=['OVERVIEW','PATCHES','OPERATORS','MODULATION','EFFECTS','SYSTEM','SEQUENCES','SD PRESETS'];
const pages=[];const colors=[0x101820,0x19252f,0x21323f,0x344c5c,0xdce8ed,0x829ba9,0xefad73,0x9dcdb7,0xb7a4e2,0x85c9d1,0xd98888,0x0b1218,0x172733,0x302c29,0x293a38,0x795b40];
const fg=[4,5,6,7,8,9,10,3];
const external=Array(1024).fill(32);
function setExternal(at,text,width=16){for(let i=0;i<width;i++)external[at+i]=(text[i]??' ').charCodeAt(0);}
['PIANO 2','ORGAN 1','BASS 3','BRASS 2'].forEach((n,i)=>setExternal(i*16,n));
setExternal(64,'APP EDIT OFFLINE',32);
setExternal(96,'APP EDIT OFFLINE',32);
for(let i=0;i<8;i++)setExternal(128+i*32,'CONNECT APP TO READ PARAMETERS',32);
for(let i=0;i<8;i++)setExternal(384+i*32,'--',32);
for(let i=0;i<32;i++)setExternal(640+i*6,`K${String(i+1).padStart(2,'0')}`,6);
setExternal(832,'SLOT 1',16);setExternal(848,'OP 1',16);setExternal(864,'READ ONLY',16);setExternal(880,'READ ONLY',16);setExternal(896,'APP CONTROL',16);
setExternal(512,'SD LIBRARY NOT MOUNTED',32);setExternal(544,'NO FILES LOADED',32);
setExternal(576,'CONNECT APP TO CHECK STORAGE',32);setExternal(608,'RECORDING IS CURRENTLY IN RAM',32);
for(let p=0;p<names.length;p++){
 const a=Array.from({length:45},()=>Array(128).fill(0));
 const box=(x,y,w,h,bg=1)=>{for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)if(yy<45&&xx<106)a[yy][xx]=(bg<<14);};
 const text=(x,y,t,c=0)=>{for(let i=0;i<t.length&&x+i<106;i++)a[y][x+i]=(a[y][x+i]&0x3c000)|(c<<11)|t.toUpperCase().charCodeAt(i);};
 const ext=(x,y,at,len=16,c=0)=>{for(let i=0;i<len;i++)a[y][x+i]=(a[y][x+i]&0x3c000)|(c<<11)|(128+at+i);};
 const number=(x,y,field,digits=8,c=3)=>{for(let i=0;i<digits;i++)a[y][x+i]=(a[y][x+i]&0x3c000)|(c<<11)|(1152+field*16+i);};
 box(0,0,106,3,12);text(2,1,'SYNTHSTRING',2);text(20,1,'TANG MEGA 60K',1);ext(43,1,64,32,3);
 text(78,1,'TOUCH',1);a[1][84]=(12<<14)|(3<<11)|1120;text(86,1,'/4 HOLD JOY',1);
 // Shared tab rows: background13 marks navigation, foreground bits hold page ID.
 // The pixel stage applies active colors; all eight pages reuse the same ROM.
 for(let tab=0;tab<names.length;tab++){
  const x=2+tab*13;
  box(x,4,12,3,13);
  for(let y=4;y<7;y++)for(let column=x;column<x+12;column++)a[y][column]|=tab<<11;
  text(x+Math.floor((12-names[tab].length)/2),5,names[tab],tab);
 }
 text(2,8,`${p+1} / ${names[p]}`,0);text(78,8,'LIVE FPGA / 720P',3);
 if(p===0){
  for(let n=0;n<3;n++)box(2+n*35,10,33,14);
  text(3,11,'REALTIME WAVE');text(38,11,'FREQUENCY SPECTRUM');text(73,11,'SPECTROGRAM');
  text(3,12,'RISING EDGE / AUTO RANGE',1);text(38,12,'LOG MAGNITUDE / DFT 256',1);text(73,12,'LIVE HISTORY',1);
  text(4,23,'256 SAMPLES / 5.24 MS',1);text(39,23,'0.19 - 12.21 KHZ',1);text(74,23,'NEWEST AT BOTTOM',1);
  box(2,25,62,9);box(66,25,38,9);text(3,26,'RESIDENT PATCHES');
  for(let n=0;n<4;n++){let x=3+(n%2)*30,y=28+Math.floor(n/2)*3;text(x,y,`S${n+1}`,1);ext(x+3,y,n*16,16,2);}
  text(67,26,'AUDIO HEALTH');text(67,28,'KEY TO PCM US');number(85,28,1,8);
  text(67,30,'UNDERRUNS');number(85,30,2,8);text(67,32,'DRY OUTPUT / FX DISABLED',1);
 } else if(p===1){
  box(2,10,33,22);box(36,10,68,22);text(3,11,'DESTINATION SLOT');text(37,11,'RESIDENT PATCHES / REAL DATA');
  for(let n=0;n<4;n++){text(4,15+n*4,`SLOT ${n+1}`,2);ext(12,15+n*4,n*16,16);text(38,15+n*4,`S${n+1}`,1);ext(42,15+n*4,n*16,16,3);}
  text(37,13,'LOAD FM1 OR NATIVE PRESETS FROM APP',1);text(37,31,'EDITING USES THE EXISTING ACK / CRC LINK',1);
 } else if(p===2){
  box(2,10,33,22);box(36,10,68,22);text(3,11,'SIX OPERATOR ENGINE');text(37,11,'SELECTED OPERATOR / LIVE PARAMETERS');
  text(3,14,'6 LOGICAL OPS / VOICE',1);text(3,16,'DDS / PM / FM / AM',3);text(3,18,'WAVETABLE / DX EG',3);text(3,21,'REAL ROUTING IN APP',1);text(3,24,'E1 SLOT / E2 OP',2);
  for(let n=0;n<8;n++)ext(38,14+n*2,128+n*32,32,n<4?2:1);
 } else if(p===3){
  box(2,10,33,22);box(36,10,68,22);text(3,11,'LOW FREQUENCY OSC');text(37,11,'MODULATION MATRIX');
  text(3,14,'HARDWARE LFO / ROUTES',3);text(3,17,'CONFIGURE VIA APP',1);text(3,20,'AUDIO RATE DSP',1);
  for(let n=0;n<8;n++)ext(38,14+n*2,384+n*32,32,4);
 } else if(p===4){
  box(2,10,50,24);box(54,10,50,24);text(3,11,'DELAY',5);text(55,11,'REVERB',5);
  for(const x of [3,55]){text(x,15,'NOT COMPILED',6);text(x,18,'CURRENT FIRMWARE USES DRY AUDIO',1);text(x,21,'NO INACTIVE PARAMETER CONTROLS',1);}
  text(3,30,'VOICE MIX > MASTER > PT8211 DAC',3);
 } else if(p===5){
  box(2,10,50,24);box(54,10,50,24);text(3,11,'SYSTEM / REAL TELEMETRY');text(55,11,'DISPLAY CONTROL');
  text(3,14,'CORE 50 MHZ / PCM 48828.125 HZ',3);text(3,16,'PIXEL 73.333 MHZ / 59.259 HZ',1);text(3,18,'KEY TO PCM US');number(36,18,1);
  text(3,20,'UNDERRUNS HEX');number(36,20,2);text(3,22,'UART ERRORS HEX');number(36,22,3);text(3,24,'PCM FRAMES HEX');number(36,24,4);text(3,26,'KEY BITMAP HEX');number(36,26,0);
  text(55,14,'LEFT / RIGHT : PAGE',2);text(55,17,'UP / DOWN : OPERATOR',2);text(55,20,'E1 SLOT / E2 OP',2);text(55,23,'E3 LEVEL / E4 RATIO / E5 MASTER',2);text(55,26,'EDITING REQUIRES THE APP LINK',1);text(55,29,'ONE MOVE / RETURN TO CENTRE',1);
 } else {
  box(2,10,50,24);box(54,10,50,24);
  ext(3,11,512,32,2);ext(55,11,544,32,3);
  for(let n=0;n<8;n++)ext(3,14+n*2,128+n*32,32,n===0?2:0);
  text(55,15,'UP / DOWN : SELECT',2);text(55,18,'PRESS JOYSTICK : LOAD',2);
  text(55,21,'E1 : DESTINATION SLOT',2);text(55,24,'SW5 PREVIOUS / SW6 NEXT',1);
  ext(55,28,576,32,3);ext(55,31,608,32,1);
 }
 box(0,35,106,4,12);text(2,35,'KEY MATRIX',1);text(2,37,'32 KEYS',3);
 for(let k=0;k<32;k++){let x=14+(k%8)*7,y=35+Math.floor(k/8);box(x,y,6,1,15);ext(x,y,640+k*6,6,1);}
 text(73,35,'PHYSICAL KEYS',1);text(73,37,'LIVE / NO HOST POLLING',3);
 for(let position=0;position<5;position++){const e=4-position;box(2+position*21,40,20,3);text(3+position*21,40,['E1 SLOT','E2 OPERATOR','E3 LEVEL','E4 RATIO','E5 MASTER'][e],1);ext(3+position*21,42,832+e*16,16,e===4?2:0);}
 text(2,44,'SYNTHUI / CHARACTER PIPELINE / NO FRAMEBUFFER',1);text(66,44,'AUDIO NEVER WAITS FOR DISPLAY',3);
 pages.push(a);
}
const rows=[Array(128).fill(0)],index=new Map([[rows[0].join(','),0]]),pointers=Array(512).fill(0);
for(let p=0;p<names.length;p++)for(let y=0;y<45;y++){const row=pages[p][y],key=row.join(',');if(!index.has(key)){index.set(key,rows.length);rows.push(row);}pointers[p*64+y]=index.get(key);}
// Keep the address/pixel pipeline unchanged; pad to physical 1024x18 banks,
// rather than doubling a partially occupied ROM to a power-of-two capacity.
const rtl=await fs.readFile(new URL('../rtl/SynthDisplayVideo.v',import.meta.url),'utf8');
const depth=Number(rtl.match(/localparam\s+C_CELL_DEPTH\s*=\s*(\d+)\s*;/)?.[1]);
if(depth!==8192+2048+1024||rows.length*128>depth)
 throw new Error(`HDMI rows require ${rows.length*128} cells; check C_CELL_DEPTH=${depth}`);
const chars=rows.flat();while(chars.length<depth)chars.push(0);
const font=Array(1024).fill(0);for(let c=0;c<128;c++){let bits=FONT[String.fromCharCode(c)]??'0'.repeat(35);for(let y=0;y<7;y++)font[c*8+y]=parseInt(bits.slice(y*5,y*5+5),2);}
const coefficients=Array.from({length:256},(_,i)=>{const re=Math.round(32767*Math.cos(2*Math.PI*i/256))&65535,im=Math.round(32767*Math.sin(2*Math.PI*i/256))&65535;return (BigInt(im)<<16n)|BigInt(re);});
const write=async(n,a,w)=>fs.writeFile(new URL(n,root),a.map(v=>v.toString(16).padStart(w,'0')).join('\n')+'\n');
await write('rows.hex',pointers,2);await write('cells.hex',chars,5);await write('font.hex',font,2);await write('text.hex',external,2);await write('dft.hex',coefficients,8);
await write('cells_main.hex',chars.slice(0,8192),5);
await write('cells_middle.hex',chars.slice(8192,10240),5);
await write('cells_tail.hex',chars.slice(10240,11264),5);
await write('history.hex',Array(4096).fill(0),2);
await fs.writeFile(new URL('manifest.json',root),JSON.stringify({width:1280,height:720,cell:[12,16],rows:rows.length,depth,colors,fg,names},null,2));
console.log({rows:rows.length,depth,romBits:depth*18+512*8+1024*5});
