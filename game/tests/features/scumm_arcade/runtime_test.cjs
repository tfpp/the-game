// Real interpreter test: two independent WASM instances, different batching and
// scheduling, plus a late replay. Run with node; assets must have been built first.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../../features/scumm_arcade/runtime');
const Driver = require(path.join(root, 'driver.js'));
const factory = require(path.join(root, 'dist/scummvm.js'));
const wasm = fs.readFileSync(path.join(root, 'dist/scummvm.wasm'));
function create() { return new Driver(factory, wasm); }
function events(tick) {
    if (tick === 200) return [[5,160,100,27]]; // Skip the opening scene.
    if (tick === 201) return [[6,160,100,27]];
    if (tick % 311 === 0) return [[0, tick % 320, 80, 0], [1,tick % 320,80,0]];
    if (tick % 311 === 1) return [[2,(tick-1) % 320,80,0]];
    if (tick % 83 === 0) return [[5,160,100,46]];
    if (tick % 83 === 1) return [[6,160,100,46]];
    return [];
}
async function simulate(driver, count, batchSize, jitter = false) {
    let packet;
    while (driver.tick < count) {
        const size = Math.min(batchSize, count - driver.tick);
        const frames = Array.from({length:size}, (_, i) => events(driver.tick + i));
        packet = await driver.advance(frames);
        driver.heardAudio ||= packet.slice(256008).some(value => value !== 0);
        if (jitter && driver.tick % 100 === 0) await new Promise(r => setTimeout(r, 7));
    }
    return packet;
}
(async () => {
    const first = create(), second = create();
    await Promise.all([first.ready, second.ready]);
    const [a,b] = await Promise.all([simulate(first, 3000, 5, true), simulate(second, 3000, 37)]);
    assert.ok(first.heardAudio, 'The demo must produce real PCM audio');
    assert.equal(first.hash, second.hash, 'Different scheduling must not change the game');
    assert.deepEqual(a.slice(8,256008), b.slice(8,256008));
    const late = create();
    await late.ready;
    await simulate(late, 3000, 250);
    assert.equal(first.hash, late.hash, 'Late replay must recreate the live game');
    const baseline = first.hash;
    const floatPacket = await first.advance([[]], true);
    const rawPacket = await second.advance([[]]);
    const floats = new Float32Array(floatPacket.buffer, floatPacket.byteOffset + 256008);
    const shorts = new Int16Array(rawPacket.buffer, rawPacket.byteOffset + 256008);
    assert.equal(floats.length, shorts.length);
    for (let i = 0; i < floats.length; i++) assert.equal(floats[i], shorts[i] / 32768);
    assert.equal(first.hash, second.hash, 'Audio transport conversion cannot alter simulation');
    const before = first.tick;
    await new Promise(r => setTimeout(r, 150));
    assert.equal(first.tick, before, 'No game time passes without server ticks');
    fs.writeFileSync('/tmp/scumm-arcade-test.rgba', a.slice(8,256008));
    console.log(`PASS: three independent instances agree after 3000 ticks: ${baseline}`);
    process.exit(0);
})().catch(error => { console.error(error); process.exit(1); });
