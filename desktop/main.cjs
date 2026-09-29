'use strict';

const { app, BrowserWindow, Menu, dialog } = require('electron');
const { GAME_URL, canNavigate, canPermit } = require('./policy.cjs');

let window;

function createWindow() {
  window = new BrowserWindow({
    title: 'The Game', width: 1280, height: 800, minWidth: 640, minHeight: 480,
    backgroundColor: '#101014',
    webPreferences: {
      nodeIntegration: false, contextIsolation: true, sandbox: true,
      webSecurity: true, webviewTag: false,
      partition: 'persist:the-game'
    }
  });
  const current = window;
  const contents = current.webContents;
  const session = contents.session;
  session.setPermissionRequestHandler((sender, permission, callback, details) => {
    callback(sender === contents && details.isMainFrame === true &&
      canPermit(permission, details.requestingUrl));
  });
  session.setPermissionCheckHandler((sender, permission, origin) =>
    sender === contents && origin === 'https://tfpp.github.io' &&
    canPermit(permission, contents.getURL()));
  session.on('will-download', (event) => event.preventDefault());
  contents.setWindowOpenHandler(() => ({ action: 'deny' }));
  for (const eventName of ['will-navigate', 'will-redirect']) {
    contents.on(eventName, (event, url) => {
      if (!canNavigate(url)) event.preventDefault();
    });
  }
  contents.on('will-attach-webview', (event) => event.preventDefault());
  contents.on('did-fail-load', async (_event, code, _description, _url, mainFrame) => {
    if (!mainFrame || code === -3 || current.isDestroyed()) return;
    const { response } = await dialog.showMessageBox(current, {
      type: 'error', title: 'Cannot load The Game',
      message: 'The website could not be loaded. Check your internet connection.',
      buttons: ['Retry', 'Close'], defaultId: 0, cancelId: 1
    });
    if (current.isDestroyed()) return;
    if (response === 0) loadGame(current);
    else current.close();
  });
  current.on('closed', () => { window = null; });
  loadGame(current);
}

function loadGame(target) {
  // did-fail-load presents a retry dialog; never print URLs containing auth fragments.
  target.loadURL(GAME_URL).catch(() => {});
}

app.whenReady().then(() => {
  const menu = [
    ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
    { label: 'Game', submenu: [
      { label: 'Return to game', click: () => window && loadGame(window) },
      { role: 'reload' }, { role: 'togglefullscreen' }, { type: 'separator' },
      { role: process.platform === 'darwin' ? 'close' : 'quit' }
    ] },
    { role: 'editMenu' }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(menu));
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
