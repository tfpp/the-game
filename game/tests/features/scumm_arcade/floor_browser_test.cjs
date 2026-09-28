// Five independent browser Workers must match native replay and survive another's restart.
// Run floor_runtime_test.cjs first to generate /tmp/scumm-floor-hashes.json.
const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../../features/scumm_arcade/runtime');
const expected = JSON.parse(fs.readFileSync('/tmp/scumm-floor-hashes.json'));
const server = http.createServer((req,res)=>{
 if(req.url==='/') return res.end('<!doctype html><title>Five arcade workers</title>');
 const file=path.join(root,req.url);
 if(!fs.existsSync(file)) return res.writeHead(404).end();
 res.end(fs.readFileSync(file));
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 try {
  const page=await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.addScriptTag({url:'/browser.js'});
  const actual=await page.evaluate(async()=>{
   const engine=await(await fetch('/dist/scummvm.js')).text();
   const driver=await(await fetch('/driver.js')).text();
   const wasm=new Uint8Array(await(await fetch('/dist/scummvm.wasm')).arrayBuffer());
   const wait=async(w,predicate)=>{
    for(let i=0;i<6000;i++) {
     if(w.status==='failed') throw Error(w.error);
     if(predicate())return;
     await new Promise(r=>setTimeout(r,10));
    } throw Error('Worker timeout');
   };
   function events(game,tick) {
    if(game==='tentacle')return [];
    if(game==='pass') {
     if(tick===500)return [[0,45,40,0],[1,45,40,0]];
     if(tick===501)return [[2,45,40,0]];
     return [];
    }
    if(tick===200)return [[5,160,100,27]];
    if(tick===201)return [[6,160,100,27]];
    if(tick%311===0)return [[0,tick%320,80,0],[1,tick%320,80,0]];
    if(tick%311===1)return [[2,(tick-1)%320,80,0]];
    return [];
   }
   const output={};
   await Promise.all(['monkey','samnmax','atlantis','pass','tentacle'].map(async game=>{
    const data=game==='monkey'?null:new Uint8Array(await(await fetch('/dist/'+game+'.pak')).arrayBuffer());
    const worker=createScummArcade(game);
    worker.start(engine,driver,wasm,game,data);
    await wait(worker,()=>worker.status==='ready');
    let tick=0,hash;
    while(tick<3000) {
     worker.send(JSON.stringify(Array.from({length:250},(_,i)=>events(game,tick+i))));
     await wait(worker,()=>worker.packet);
     const packet=new DataView(worker.take());
     tick=packet.getUint32(0,true); hash=packet.getUint32(4,true);
    }
    output[game]={tick,hash};
   }));
   scummArcades.monkey.stop();
   scummArcades.samnmax.send(JSON.stringify([[]]));
   await wait(scummArcades.samnmax,()=>scummArcades.samnmax.packet);
   if(new DataView(scummArcades.samnmax.take()).getUint32(0,true)!==3001)throw Error('Cabinets interfered');
   for(const worker of Object.values(scummArcades))worker.stop();
   return output;
  });
  for(const [game,result] of Object.entries(actual))assert.equal(result.hash,expected[game].hash,game);
  console.log('PASS: 5 simultaneous Workers match native hashes at tick 3000; stopping one leaves others running.',actual);
 } finally {await browser.close();server.close();}
})().catch(error=>{console.error(error);server.close();process.exitCode=1});
