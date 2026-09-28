// SPDX-License-Identifier: GPL-3.0-or-later
// Shared by the browser and the desktop worker. There are no wall-clock inputs.
class ArcadeDriver {
    constructor(factory, wasmBinary, game = 'monkey', data = null) {
        if (!['monkey', 'samnmax', 'atlantis', 'pass', 'tentacle'].includes(game)) throw new Error('Unknown arcade game');
        this.tick = 0;
        this.hash = 2166136261;
        this.module = null;
        this.waiter = null;
        this.stopped = false;
        this.ready = new Promise((resolve, reject) => {
            this.reject = reject;
            factory({
                wasmBinary,
                noInitialRun: true,
                print: () => {},
                printErr: text => console.error('[scumm]', text),
                onAbort: message => reject(new Error(String(message))),
            }).then(module => {
                this.module = module;
                module.FS.mkdir('/saves');
                if (game !== 'monkey') this.installDemo(data);
                module.arcadeOnYield = () => {
                    if (this.stopped) return;
                    const done = this.waiter;
                    this.waiter = null;
                    if (done) done();
                    else resolve();
                };
                module.callMain([
                    '--config=/arcade.ini', `--path=${game === 'monkey' ? '/demo' : '/arcade-demo'}`, '--savepath=/saves',
                    '--music-driver=adlib', '--output-rate=22050', '--subtitles',
                    '--copy-protection', game
                ]);
            }).catch(reject);
        });
    }
    installDemo(data) {
        if (!data || data.length < 4 || data.length > 16 * 1024 * 1024) throw new Error('Invalid demo package');
        const bytes = new Uint8Array(data);
        const length = new DataView(bytes.buffer, bytes.byteOffset).getUint32(0, true);
        if (length > 65536 || length + 4 > bytes.length) throw new Error('Invalid demo header');
        const files = JSON.parse(new TextDecoder().decode(bytes.subarray(4, 4 + length)));
        if (!Array.isArray(files) || files.length > 128) throw new Error('Invalid demo index');
        this.module.FS.mkdir('/arcade-demo');
        let offset = 4 + length;
        for (const [name, size] of files) {
            if (!/^[a-zA-Z0-9_.-]+$/.test(name) || name === '.' || name === '..' ||
                !Number.isSafeInteger(size) || size < 0 || offset + size > bytes.length)
                throw new Error('Invalid demo file');
            this.module.FS.writeFile('/arcade-demo/' + name, bytes.subarray(offset, offset + size));
            offset += size;
        }
        if (offset !== bytes.length) throw new Error('Unexpected demo data');
    }
    async advance(frames, floatAudio = false) {
        await this.ready;
        if (this.stopped) throw new Error('Runtime stopped');
        if (!Array.isArray(frames) || frames.length > 250) throw new Error('Invalid batch');
        const sound = [];
        for (const events of frames) {
            for (const e of events) this.module._arcade_input(...e);
            await new Promise(resolve => {
                this.waiter = resolve;
                const resume = this.module.arcadeResume;
                this.module.arcadeResume = null;
                resume();
            });
            this.tick++;
            const pixels = this.module.arcadePixels;
            // A rolling presentation checksum spots visible/audio divergence and is
            // compared at the SAME tick, independent of transport batching.
            let hash = this.hash;
            for (let i = 0; i < pixels.length; i++) hash = Math.imul(hash ^ pixels[i], 16777619);
            const pcm = this.module.arcadePCM;
            for (let i = 0; i < pcm.length; i++) hash = Math.imul(hash ^ pcm[i], 16777619);
            this.hash = hash >>> 0;
            // Keep the newest audio even after a delayed/catch-up batch.
            sound.push(pcm);
            if (sound.length > 10) sound.shift();
        }
        const pixels = this.module.arcadePixels || new Uint8Array(320 * 200 * 4);
        const audio = sound.map(pcm => {
            if (!floatAudio) return pcm;
            const samples = new Int16Array(pcm.buffer, pcm.byteOffset, pcm.byteLength / 2);
            const floats = new Float32Array(samples.length);
            for (let i = 0; i < samples.length; i++) floats[i] = samples[i] / 32768;
            return new Uint8Array(floats.buffer);
        });
        const pcmSize = audio.reduce((n, a) => n + a.length, 0);
        const result = new Uint8Array(8 + pixels.length + pcmSize);
        const header = new DataView(result.buffer);
        header.setUint32(0, this.tick, true);
        header.setUint32(4, this.hash, true);
        result.set(pixels, 8);
        let offset = 8 + pixels.length;
        for (const pcm of audio) { result.set(pcm, offset); offset += pcm.length; }
        return result;
    }
    stop() { this.stopped = true; }
}
if (typeof module !== 'undefined') module.exports = ArcadeDriver;
else globalThis.ArcadeDriver = ArcadeDriver;
