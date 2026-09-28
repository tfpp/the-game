// SPDX-License-Identifier: GPL-3.0-or-later
// One instance in a Worker prevents fast replay from blocking the Godot UI.
globalThis.scummArcades ??= {};
globalThis.createScummArcade = function(id) {
 const instance = {
    worker: null, packet: null, status: 'stopped', error: '',
    start(engine, driver, wasm, game = 'monkey', data = null) {
        this.stop();
        this.status = 'loading';
        this.error = '';
        const workerSource = engine + '\n' + driver + `
            let runtime;
            onmessage = async event => {
                try {
                    if (!runtime) {
                        runtime = new ArcadeDriver(ScummArcade, event.data.wasm, event.data.game, event.data.data);
                        await runtime.ready;
                        postMessage('ready');
                    } else {
                        const packet = await runtime.advance(JSON.parse(event.data), true);
                        postMessage(packet.buffer, [packet.buffer]);
                    }
                } catch (error) { postMessage({error: String(error)}); }
            };
        `;
        const url = URL.createObjectURL(new Blob([workerSource], {type: 'text/javascript'}));
        this.worker = new Worker(url);
        URL.revokeObjectURL(url);
        this.worker.onmessage = event => {
            if (event.data === 'ready') this.status = 'ready';
            else if (event.data.error) { this.status = 'failed'; this.error = event.data.error; }
            else this.packet = event.data;
        };
        this.worker.onerror = event => { this.status = 'failed'; this.error = event.message; };
        // Godot's JavaScriptObject arguments support strings, not PackedByteArray.
        const decode = value => typeof value === 'string'
            ? Uint8Array.from(atob(value), c => c.charCodeAt(0)) : new Uint8Array(value || []);
        const bytes = decode(wasm), assets = decode(data);
        this.worker.postMessage({wasm: bytes, game, data: assets}, [bytes.buffer, assets.buffer]);
    },
    send(json) { this.worker.postMessage(json); },
    take() { const result = this.packet; this.packet = null; return result; },
    stop() {
        if (this.worker) this.worker.terminate();
        this.worker = null; this.packet = null; this.status = 'stopped';
    }
 };
 globalThis.scummArcades[id] = instance;
 return instance;
};
// Keep the single-instance runtime test API; Godot creates named instances.
globalThis.scummArcade ??= globalThis.createScummArcade('default');
