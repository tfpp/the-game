// SPDX-License-Identifier: GPL-3.0-or-later
// Local transport only: every desktop process has its OWN emulator. No remote
// peer receives these pixels. The network carries ticks and inputs in cabinet.gd.
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const ArcadeDriver = require('./driver.js');
const factory = require('./scummvm.js');
const game = process.argv[4] || 'monkey';
const data = game === 'monkey' ? null : fs.readFileSync(path.join(__dirname, 'demo.pak'));
const driver = new ArcadeDriver(factory, fs.readFileSync(path.join(__dirname, 'scummvm.wasm')), game, data);
const socket = net.connect(Number(process.argv[2]), '127.0.0.1');
let buffer = Buffer.alloc(0);
let busy = false;
function send(data) {
    const header = Buffer.alloc(4);
    header.writeUInt32LE(data.length);
    socket.write(Buffer.concat([header, Buffer.from(data)]));
}
socket.on('connect', async () => {
    try { await driver.ready; send(Buffer.from(process.argv[3])); }
    catch (error) { console.error(error); process.exit(1); }
});
socket.on('data', async data => {
    buffer = Buffer.concat([buffer, data]);
    if (buffer.length > 262144) return socket.destroy(new Error('Oversized request'));
    if (busy) return;
    busy = true;
    try {
        while (buffer.length >= 4 && buffer.length >= 4 + buffer.readUInt32LE(0)) {
            const length = buffer.readUInt32LE(0);
            const request = JSON.parse(buffer.subarray(4, 4 + length).toString());
            buffer = buffer.subarray(4 + length);
            send(await driver.advance(request));
        }
    } catch (error) { console.error(error); process.exit(1); }
    finally { busy = false; }
});
socket.on('close', () => process.exit(0));
socket.on('error', error => { console.error(error); process.exit(1); });
