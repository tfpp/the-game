# The Game desktop

An Electron window for https://tfpp.github.io/the-game/, for Linux, macOS and
Windows ("PC"). It loads the live website, so game updates arrive on reload and
multiplayer uses the same accounts and server as browser players. Internet access
is required to load the game; the in-game **Play offline** option still means solo
play after loading, not an install containing offline game assets.

## Install with curl

Requires **Node.js 22.12+**, npm and curl. Run in Terminal on macOS/Linux or in
**Git Bash** on Windows (with Node.js installed for Windows):

```sh
curl -fsSL https://raw.githubusercontent.com/tfpp/the-game/main/desktop/install.sh | bash
```

The installer resolves `main` to one commit, downloads only the desktop sources and
lockfile, runs `npm ci`, and packages Electron for the current x64/arm64 host. It
installs for your user without sudo. Close the app before rerunning to update.
Failed downloads or builds leave the previous installation intact.

| OS | Default install | Launch |
| --- | --- | --- |
| macOS | `~/Applications/TheGame/TheGame.app` | Open the app in Finder |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/the-game-desktop` | The Game in your applications menu |
| Windows (Git Bash) | `%LOCALAPPDATA%\TheGame` | Open `TheGame.exe` in Explorer |

These are locally built, unsigned apps; signing/notarization and prebuilt downloads
are not provided. Linux still needs a graphical desktop, Electron's system libraries
and working Chromium sandbox support. The installer does not change system packages
or disable the sandbox. Internet access is required for installation and game startup.

To download and inspect the script before running, or choose an install directory:

```sh
curl -fsSLo install-the-game.sh https://raw.githubusercontent.com/tfpp/the-game/main/desktop/install.sh
less install-the-game.sh
bash install-the-game.sh --prefix "$HOME/Apps/TheGame"
```

`--ref <commit-or-branch>` selects the source revision; a full commit SHA pins it.
For a fully pinned installation, download the script from that same SHA instead of
`main`. `--prefix` must be an absolute path (a Git Bash path on Windows). Existing
folders without this installer's marker are never replaced. Concurrent installs to
the same directory are rejected.

To uninstall, delete the install directory and, on Linux,
`~/.local/share/applications/the-game.desktop` (or its `$XDG_DATA_HOME` equivalent).
Your Electron profile is kept, so reinstalling preserves your desktop session.

## Run and package

On a development machine with Node.js 22.12+ and npm:

```sh
cd desktop
npm ci
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
version. The game continues to show its deployed version. Dependencies and their
integrity hashes are pinned in the committed npm lockfile.

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
