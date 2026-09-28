// Independent interpreters must agree for every packaged cabinet demo.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../../features/scumm_arcade/runtime');
const Driver = require(path.join(root, 'driver.js'));
const factory = require(path.join(root, 'dist/scummvm.js'));
const wasm = fs.readFileSync(path.join(root, 'dist/scummvm.wasm'));
const games = ['monkey', 'samnmax', 'atlantis', 'pass', 'tentacle'];
function events(game, tick) {
    if (game === 'tentacle') return [];
    if (game === 'pass') {
        if (tick === 500) return [[0,45,40,0],[1,45,40,0]];
        if (tick === 501) return [[2,45,40,0]];
        return [];
    }
    if (tick === 200) return [[5,160,100,27]];
    if (tick === 201) return [[6,160,100,27]];
    if (tick % 311 === 0) return [[0,tick%320,80,0],[1,tick%320,80,0]];
    if (tick % 311 === 1) return [[2,(tick-1)%320,80,0]];
    return [];
}
async function run(driver, game, batch) {
    await driver.ready;
    let packet, audio = false;
    while (driver.tick < 3000) {
        const frames = Array.from({length: Math.min(batch,3000-driver.tick)}, (_,i)=>events(game,driver.tick+i));
        packet = await driver.advance(frames);
        audio ||= packet.subarray(256008).some(b=>b!==0);
    }
    return {packet, audio};
}
(async()=>{
    const results = {};
    for (const game of games) {
        const data = game === 'monkey' ? null : fs.readFileSync(path.join(root,'dist',game+'.pak'));
        const a = new Driver(factory,wasm,game,data), b = new Driver(factory,wasm,game,data);
        const first = await run(a,game,5), replay = await run(b,game,37);
        assert.equal(a.hash,b.hash,game+' diverged');
        assert.equal(replay.audio, first.audio, game+' catch-up batches must retain recent audio');
        assert.deepEqual(first.packet.subarray(8,256008),replay.packet.subarray(8,256008));
        results[game] = {hash:a.hash,audio:first.audio};
        fs.writeFileSync('/tmp/scumm-'+game+'.rgba',first.packet.subarray(8,256008));
        console.log('PASS', game, results[game]);
    }
    fs.writeFileSync('/tmp/scumm-floor-hashes.json',JSON.stringify(results));
    process.exit(0);
})().catch(error=>{console.error(error);process.exit(1)});
