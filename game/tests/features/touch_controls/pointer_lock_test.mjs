// Run: node game/tests/features/touch_controls/pointer_lock_test.mjs
// Exercise the shipped inline guard without loading Godot or installing packages.
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';

const shell = readFileSync(new URL('../../../features/touch_controls/shell.html', import.meta.url), 'utf8');
const source = shell.match(/<script id="game-pointer-lock">([\s\S]*?)<\/script>/)[1];
function fixture({ focused = true, canFocus = true, request } = {}) {
    const calls = [];
    const canvas = {
        focus(options) {
            assert.equal(options.preventScroll, true);
            calls.push('canvas focus');
        },
        requestPointerLock: request && function (...args) {
            assert.equal(this, canvas);
            assert.equal(focused, true, 'Never request a lock from a background document');
            calls.push('request');
            return request(...args);
        },
    };
    const document = {
        getElementById(id) { assert.equal(id, 'canvas'); return canvas; },
        hasFocus() { return focused; },
    };
    const window = { focus() { calls.push('window focus'); focused = canFocus; } };
    runInNewContext(source, { document, window });
    return { canvas, calls, focus() { focused = true; } };
}

let f = fixture({ focused: false, request: () => undefined });
assert.equal(f.canvas.requestPointerLock(), undefined, 'Legacy void return');
assert.deepEqual(f.calls, ['window focus', 'canvas focus', 'request']);
f = fixture({ request: options => { assert.equal(options.unadjustedMovement, true); return Promise.resolve('locked'); } });
assert.equal(await f.canvas.requestPointerLock({ unadjustedMovement: true }), 'locked');
assert.deepEqual(f.calls, ['canvas focus', 'request']);
f = fixture({ focused: false, canFocus: false, request: () => Promise.resolve() });
f.canvas.requestPointerLock();
assert.deepEqual(f.calls, ['window focus', 'canvas focus'], 'No request while focus is unavailable');
f.focus();
assert.deepEqual(f.calls, ['window focus', 'canvas focus'], 'Focus gain alone must not retry');
await f.canvas.requestPointerLock();
assert.deepEqual(f.calls, ['window focus', 'canvas focus', 'canvas focus', 'request']);
let denied = true;
f = fixture({ request: () => denied ? Promise.reject(new Error('The document is not focused.')) : Promise.resolve('locked') });
// Godot ignores the return value. Verify that doing so produces no unhandled rejection.
const unhandled = [];
const onUnhandled = error => unhandled.push(error);
process.on('unhandledRejection', onUnhandled);
f.canvas.requestPointerLock();
await new Promise(resolve => setImmediate(resolve));
process.off('unhandledRejection', onUnhandled);
assert.deepEqual(unhandled, []);
assert.equal(f.calls.filter(call => call === 'request').length, 1, 'No automatic retry on rejection');
denied = false;
assert.equal(await f.canvas.requestPointerLock(), 'locked', 'A later user gesture can capture');
f = fixture({ request: () => { throw new Error('Denied'); } });
assert.doesNotThrow(() => f.canvas.requestPointerLock());
f = fixture();
assert.equal(f.canvas.requestPointerLock, undefined, 'Unsupported browsers stay unchanged');
console.log('PASS: pointer-lock focus, refusal, recovery and API compatibility');
