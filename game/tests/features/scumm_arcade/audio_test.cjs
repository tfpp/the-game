// Real WASM PCM -> Godot cabinet generator -> positional mixer -> captured samples.
// GODOT must have a working audio driver (e.g. CoreAudio on macOS).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const game = path.resolve(__dirname, '../../..');
const root = path.join(game, 'features/scumm_arcade/runtime');
const Driver = require(path.join(root, 'driver.js'));
(async () => {
    const driver = new Driver(require(path.join(root, 'dist/scummvm.js')),
        fs.readFileSync(path.join(root, 'dist/scummvm.wasm')));
    await driver.ready;
    let pcm;
    for (let tick = 0; tick < 3000; tick++) {
        // Enter the interactive demo; its opening text sequence is silent.
        let events = [];
        if (tick === 200) events = [[5,160,100,27]];
        else if (tick === 201) events = [[6,160,100,27]];
        else if (tick % 311 === 0) events = [[0,tick % 320,80,0], [1,tick % 320,80,0]];
        else if (tick % 311 === 1) events = [[2,(tick-1) % 320,80,0]];
        else if (tick % 83 === 0) events = [[5,160,100,46]];
        else if (tick % 83 === 1) events = [[6,160,100,46]];
        const packet = await driver.advance([events]);
        const samples = packet.slice(256008);
        if (samples.some(value => value !== 0)) { pcm = samples; break; }
    }
    assert.ok(pcm, 'The actual demo must produce audio');
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'scumm-audio-'));
    const file = path.join(directory, 'demo.pcm');
    fs.writeFileSync(file, pcm);
    try {
        await new Promise((resolve, reject) => {
            const child = spawn(process.env.GODOT || 'godot', [
                '--path', game, '--resolution', '320x240',
                'res://tests/features/scumm_arcade/audio_probe.tscn', '--',
                '--scumm-no-save', `--arcade-pcm=${file}`]);
            let output = '';
            const timer = setTimeout(() => { child.kill(); reject(new Error(output + '\nAudio test timed out')); }, 30000);
            child.stdout.on('data', data => { output += data; });
            child.stderr.on('data', data => { output += data; });
            child.on('error', error => { clearTimeout(timer); reject(error); });
            child.on('close', code => {
                clearTimeout(timer);
                if (code !== 0 || output.includes('SCRIPT ERROR') || !output.includes('PASS:')) reject(new Error(output));
                else { console.log(output); resolve(); }
            });
        });
    } finally { fs.rmSync(directory, {recursive:true, force:true}); }
    process.exit(0);
})().catch(error => { console.error(error); process.exit(1); });
