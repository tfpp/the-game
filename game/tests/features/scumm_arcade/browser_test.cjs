// Browser Worker must agree with the native golden replay. Requires Playwright + Chrome.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const root = path.resolve(__dirname, '../../../features/scumm_arcade/runtime/');
const server = http.createServer((req,res) => {
 const file = path.join(root, req.url);
 if (req.url === '/') { res.end('<!doctype html><title>ScummVM test</title>'); return; }
 if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
 res.end(fs.readFileSync(file));
}).listen(0, '127.0.0.1', async () => {
 const browser = await chromium.launch({headless:true, channel:"chrome"});
 try {
  const page = await browser.newPage();
  page.on('console', msg => console.log('BROWSER:', msg.text()));
  page.on('pageerror', e => console.error(e));
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.addScriptTag({url:'/browser.js'});
  const result = await page.evaluate(async () => {
   const engine = await (await fetch('/dist/scummvm.js')).text();
   const driver = await (await fetch('/driver.js')).text();
   const wasm = new Uint8Array(await (await fetch('/dist/scummvm.wasm')).arrayBuffer());
   scummArcade.start(engine, driver, wasm);
   const until = async predicate => {
    for(let i=0;i<2000;i++) {
      if(scummArcade.status === 'failed') throw Error(scummArcade.error);
      if(predicate()) return;
      await new Promise(r=>setTimeout(r,10));
    }
    throw Error('timeout: '+scummArcade.status);
   };
   await until(()=>scummArcade.status==='ready');
   function events(tick) {
    if(tick===200) return [[5,160,100,27]];
    if(tick===201) return [[6,160,100,27]];
    if(tick%311===0) return [[0,tick%320,80,0],[1,tick%320,80,0]];
    if(tick%311===1) return [[2,(tick-1)%320,80,0]];
    if(tick%83===0) return [[5,160,100,46]];
    if(tick%83===1) return [[6,160,100,46]];
    return [];
   }
   let tick=0, hash;
   while(tick<3000) {
    scummArcade.send(JSON.stringify(Array.from({length:250},(_,i)=>events(tick+i))));
    await until(()=>scummArcade.packet);
    const packet = new DataView(scummArcade.take());
    tick=packet.getUint32(0,true); hash=packet.getUint32(4,true);
   }
   scummArcade.stop();
   return {tick,hash};
  });
  console.log('RESULT',result);
  if(result.hash!==3914103221) throw Error('Browser differs from Node runtime');
 } finally { await browser.close(); server.close(); }
});
