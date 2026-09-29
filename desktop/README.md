# The Game desktop

An Electron window for https://tfpp.github.io/the-game/, for Linux, macOS and
Windows ("PC"). It loads the live website, so game updates arrive on reload and
multiplayer uses the same accounts and server as browser players. Internet access
is required to load the game; the in-game **Play offline** option still means solo
play after loading, not an install containing offline game assets.

## Run and package

On a development machine with Node.js 22.12+ and npm:

```sh
cd desktop
npm install
npm test
npm start
```

Build on the corresponding operating system:

| Host | Command | Output in `dist/` (x64 and arm64) |
| --- | --- | --- |
| Linux | `npm run package:linux` | `TheGame-linux-*/TheGame` executable |
| macOS | `npm run package:mac` | `TheGame-darwin-*/TheGame.app` |
| Windows | `npm run package:windows` | `TheGame-win32-*/TheGame.exe` |

Distribute the entire output folder, not just its executable. These are portable,
unsigned app bundles, not installers. macOS signing/notarization and Windows code
signing must be handled by the release operator before trusted public distribution.
No binaries or automatic publishing workflow are included. `npm run package` builds
only the current host/architecture. Linux needs a graphical desktop and Electron's
system libraries; do not disable the Chromium sandbox to launch it.

The manifest's `0.0.0` is a wrapper packaging placeholder, not the game's release
version. The game continues to show its deployed version. Dependencies are pinned
at the top level; this change has no generated lockfile because installing dependencies
was prohibited in the implementation environment. Release operators should generate
and review a lockfile before reproducible distribution builds.

## Use

Launch TheGame, click the game to capture the mouse, then use the existing controls
and Esc menu. The native Game menu offers reload, fullscreen and Return to game
(useful for cancelling Discord sign-in). Standard copy/paste works in login forms.
Discord authorization stays in the same app session so the existing stored verifier
survives the callback. Email verification/reset links still open in your browser;
finish those there, then sign in in the app. Browser and desktop sessions are separate.
Closing the last window quits on Linux/Windows; on macOS the app stays in the Dock
and clicking it reopens the window.

## Boundary and checks

The website owns gameplay, saves, authentication and networking. The wrapper adds
no preload, IPC bridge, Node access or game RPCs. It uses a persistent sandboxed
session, restricts top-level navigation to the game and Discord sign-in round trip,
denies popups/downloads and grants only game pointer lock/fullscreen permissions.
See [Electron security guidance](https://www.electronjs.org/docs/latest/tutorial/security).

`npm test` uses Node's built-in runner without installing dependencies. Before
shipping bundles, test each OS: launch, WebGL rendering, mouse capture/release,
fullscreen, gamepad, email and Discord sign-in/link/cancel, relaunch persistence,
solo play, joining browser players, and retry after an unavailable website. Native
runtime, OAuth-provider pages and packaged builds require manual verification;
Node tests alone cannot establish those work on each platform.
