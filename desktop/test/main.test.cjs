'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const vm = require('node:vm');
const policy = require('../policy.cjs');

async function boot(platform) {
  const app = new EventEmitter();
  app.whenReady = async () => {};
  app.quit = () => { app.quitCalled = true; };
  const windows = [];
  class Window extends EventEmitter {
    constructor(options) {
      super();
      this.options = options;
      this.webContents = new EventEmitter();
      const session = new EventEmitter();
      session.setPermissionRequestHandler = fn => { session.request = fn; };
      session.setPermissionCheckHandler = fn => { session.check = fn; };
      this.webContents.session = session;
      this.webContents.setWindowOpenHandler = fn => { this.popup = fn; };
      this.webContents.getURL = () => this.url;
      windows.push(this);
    }
    loadURL(url) { this.url = url; return Promise.resolve(); }
    isDestroyed() { return !!this.destroyed; }
    close() { this.destroyed = true; this.emit('closed'); }
    static getAllWindows() { return windows.filter(w => !w.destroyed); }
  }
  const dialog = { showMessageBox: async () => ({ response: dialog.response }) };
  const Menu = { buildFromTemplate: t => t, setApplicationMenu: t => { Menu.items = t; } };
  vm.runInNewContext(fs.readFileSync(require.resolve('../main.cjs'), 'utf8'), {
    process: { platform },
    require: name => name === 'electron' ? { app, BrowserWindow: Window, Menu, dialog } : policy
  });
  await new Promise(resolve => setImmediate(resolve));
  return { app, windows, dialog, Menu };
}

test('loads production in isolated sandbox and blocks untrusted navigation and popups', async () => {
  const { windows } = await boot('linux');
  const w = windows[0];
  assert.equal(w.url, policy.GAME_URL);
  assert.equal(w.options.webPreferences.nodeIntegration, false);
  assert.equal(w.options.webPreferences.sandbox, true);
  assert.equal(w.options.webPreferences.contextIsolation, true);
  assert.equal(w.options.webPreferences.webSecurity, true);
  assert.equal(w.popup().action, 'deny');
  for (const name of ['will-navigate', 'will-redirect']) {
    let blocked = false;
    w.webContents.emit(name, { preventDefault: () => { blocked = true; } }, 'file:///tmp/x');
    assert.equal(blocked, true);
    blocked = false;
    w.webContents.emit(name, { preventDefault: () => { blocked = true; } }, policy.GAME_URL);
    assert.equal(blocked, false);
  }
  const ses = w.webContents.session;
  let granted;
  ses.request(w.webContents, 'pointerLock', result => { granted = result; },
    { isMainFrame: true, requestingUrl: policy.GAME_URL });
  assert.equal(granted, true);
  ses.request(w.webContents, 'pointerLock', result => { granted = result; },
    { isMainFrame: false, requestingUrl: policy.GAME_URL });
  assert.equal(granted, false);
  assert.equal(ses.check(w.webContents, 'pointerLock', 'https://tfpp.github.io'), true);
  assert.equal(ses.check({}, 'pointerLock', 'https://tfpp.github.io'), false);
});

test('failed main-frame loads offer retry or close', async () => {
  const { windows, dialog } = await boot('win32');
  const w = windows[0];
  dialog.response = 0;
  w.url = 'https://discord.com/login';
  w.webContents.emit('did-fail-load', {}, -105, '', '', true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(w.url, policy.GAME_URL);
  dialog.response = 1;
  w.webContents.emit('did-fail-load', {}, -105, '', '', true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(w.destroyed, true);
});

test('macOS reopens from Dock; Windows and Linux quit with last window', async () => {
  for (const platform of ['darwin', 'linux', 'win32']) {
    const { app, windows } = await boot(platform);
    windows[0].close();
    app.emit('window-all-closed');
    assert.equal(!!app.quitCalled, platform !== 'darwin');
    if (platform === 'darwin') {
      app.emit('activate');
      assert.equal(windows.length, 2);
      assert.equal(windows[1].url, policy.GAME_URL);
    }
  }
});
