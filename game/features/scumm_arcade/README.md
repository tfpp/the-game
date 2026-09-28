# Shared adventure arcades

Five cabinets stand on the west side of the sunken gaming floor, at Y = -1.5,
Z = 8.5 and X = -13, -10.8, -8.6, -6.4, -4.2. Each runs an independent game:

| Cabinet | Demo | Interaction |
| --- | --- | --- |
| Teal | The Secret of Monkey Island, English DOS EGA | Play/watch |
| Red | Sam & Max: Hit the Road, English DOS | Play/watch |
| Gold | Indiana Jones and the Fate of Atlantis, English DOS demo 1 | Play/watch |
| Blue | Passport to Adventure, English DOS EGA | Choose Indy, Monkey Island or Loom |
| Purple | Day of the Tentacle, English DOS non-interactive | Watch |

Walk up and press **E** to enter. A free cabinet gives you control automatically
once your local game has caught up; an occupied cabinet lets you watch until it is free.
Click directly on the cabinet’s 3D screen; right-click performs the default action,
Enter confirms, and `.` skips dialogue. The play view zooms in 1.7× to frame the
screen and cabinet edges. Middle-drag to look around.
The only overlay is **Release controls & leave** (or **Leave** while watching).
Click it or press **Esc** to release the cabinet and restore your normal view.
Mouse releases outside the screen and focus loss release held buttons.
Screen input respects walls and other cabinets.
Every cabinet has separate control ownership, replay, checksums and saved progress.
Day of the Tentacle rejects gameplay input on the server. Everyone sees and hears
their own local interpreter. Each speaker fades to silence at five metres.

## Architecture

There is no video/audio transport between players. The dedicated server and every
client run the **same WASM program**, including native desktop clients. Each cabinet has its own instance; the browser
keeps a registry of separate Workers, and native runtimes use separate process/instance
directories. Restarting a cabinet cannot stop or overwrite another instance. The server
assigns validated input to immutable 20 ms ticks. Clients fetch bounded batches
of those ticks and simulate locally. Empty ticks cost no replay-log entries.

The custom backend replaces wall time with server ticks, fixes the random seed
and calendar, and advances the AdLib mixer at exactly 441 stereo samples per tick.
It supplies a 320×200 indexed screen, palette and cursor, plus mouse/key events.
It reuses ScummVM's real SCUMM interpreter, resource decoders and sound emulation.
The existing interaction and modal UI services own opening the cabinet and pausing
player movement; a separate feature is needed because slots do not run a game VM.

A late joiner starts the demo from the beginning and replays the log at up to 250
ticks per batch, with catch-up audio muted. No approximate save-file snapshots are
used. Peers compare a rolling screen/audio checksum with the **server's own** result
every 250 ticks. A mismatch stops that peer and releases its controls; reopening the
cabinet rebuilds its interpreter and replays. A client's reported hash cannot replace
the authoritative baseline. The normal game build check and a WASM content hash
prevent mixing interpreter versions.

Control requests validate the authenticated sender, runtime identity, range,
facing and occlusion. Inputs also check the current owner, session generation,
range, event shape and limits. Leaving, disconnecting, moving away or losing the
six-second lease releases controls and held buttons. The view renews its lease
while open. Restart increments the generation, clearing replay and checksums.

## Runtime and shipping

- Browser: a dedicated Worker, loaded from the exported game assets; no additional
  website, CDN, cross-origin headers, plugins or browser extensions.
- Native clients and dedicated server: Node.js 18+ on PATH, or launch Godot with
  `-- --scumm-node=/absolute/path/to/node`. The server Dockerfile installs Node.
- Native pixel/audio transfer is private local IPC between that Godot process and
  its own child interpreter. It binds to loopback with a random handshake token.
- `runtime/dist/scummvm.js` and `.wasm` are included in both export presets. The
  checked-in build is ready to use; compilation is only needed to change the backend.
- Progress autosaves every five seconds, on peer disconnect and clean shutdown.
  The server restores the shared run after restarting; reconnecting players receive
  its replay automatically. The empty dedicated server pauses the arcade. The replay
  remains capped at one hour or 32,768 inputs. Restart clears the current saved run.
  Long sessions still take longer to replay: these are durable input-history
  checkpoints, not ScummVM savegames or instant WASM memory snapshots.
- Scope: these five 320×200 DOS demos, mouse and basic keyboard controls. ScummVM's
  save/load UI and other games are not exposed. Desktop use requires Node.js.

## Progress storage

The server owns the save; players never upload a replacement. Saves contain the
runtime fingerprint, committed tick and validated sparse input history. A SHA-256
integrity check, bounded decoder, temporary-file replacement and previous-save
backup protect against incomplete writes and damaged files. Invalid or incompatible
saves are reported in cabinet state and preserved until the operator explicitly restarts.
Controller leases and held buttons do not survive a restore. Clients must catch up
before taking control. A hard crash can lose up to five seconds since the last save.

Default locations are `user://scumm_arcade/server-7777.sav` (port-specific) and
`user://scumm_arcade/offline.sav` for Monkey Island. Other cabinets append their
game ID (`.samnmax`, `.atlantis`, `.pass`, `.tentacle`) to that base path, including
when a custom path is supplied. Existing Monkey Island saves keep their original
runtime fingerprint and filename. Override the base path with
`-- --scumm-save-path=/persistent-volume/arcade.sav`; `--scumm-no-save` disables
storage for isolated tests. Keep the `.sav` and `.sav.bak` files together.

**Container deployments must mount persistent storage** and pass the override above
to survive replacement of the container. The current image puts `user://` in `/tmp`,
which survives a game-process restart but is not durable across container replacement.
The volume must be writable by the image's UID 10010. This change does not deploy
or configure an external storage volume.

This store belongs to the arcade: the existing character-memory store tracks account
positions, and SettingsStore tracks local preferences. Neither owns shared emulator
progress. Existing Network role changes and disconnect signals remain the authority
for saving, pausing and handing over controls.

## Rebuild

Install/activate **Emscripten 3.1.74**, Python 3.12+, make and Info-ZIP `unzip`, then run:

```sh
python3 game/features/scumm_arcade/runtime/build.py --emsdk=/path/to/emsdk
```

The build script downloads ScummVM **v2.9.0** and the demo, checks their SHA-256
hashes, applies `arcade_backend.cpp` as the null backend, and compiles only SCUMM
(without HE or SCUMM 7/8). Its two configure edits select that backend and remove
the standalone browser shell. All source changes are in this directory; the build
cache goes to the repo's ignored `build/scumm-arcade/` directory.

The additional four demos are hash-pinned by `runtime/build_demos.py` and packaged
as individual `.pak` data files (length-prefixed JSON index followed by raw bytes).
Only engine data and original readmes are included; DOS executables are omitted.
They are mounted into each interpreter's own memory filesystem. Regenerate just
the packages without rebuilding WASM:

```sh
python3 game/features/scumm_arcade/runtime/build_demos.py
```

Passport uses an old ZIP implode method, so its extraction requires `unzip`.


Source and assets:

- [ScummVM 2.9.0 source](https://github.com/scummvm/scummvm/tree/v2.9.0)
- [Original demo listing](https://www.scummvm.org/demos/)
- [Sam & Max DOS demo](https://downloads.scummvm.org/frs/demos/scumm/samnmax-dos-demo-en.zip)
- [Fate of Atlantis DOS demo](https://downloads.scummvm.org/frs/demos/scumm/atlantis-dos-demo1-en.zip)
- [Passport to Adventure DOS demo](https://downloads.scummvm.org/frs/demos/scumm/pass-dos-en.zip)
- [Day of the Tentacle display demo](https://downloads.scummvm.org/frs/demos/scumm/dott-dos-ni-demo-en.zip)
- [English EGA demo archive](https://downloads.scummvm.org/frs/demos/scumm/monkey1-dos-ega-demo-en.zip)

The backend, JS runtime and compiled interpreter are GPL-3.0-or-later. ScummVM
attribution and license are in `runtime/SCUMMVM-COPYRIGHT` and `runtime/COPYING`.
The games and their demo assets are Lucasfilm/LucasArts property, separate from
ScummVM's license. Original readmes are retained where supplied in the archives.

## Verification

```sh
harness/verify.sh
node game/tests/features/scumm_arcade/runtime_test.cjs
node game/tests/features/scumm_arcade/browser_test.cjs # requires Playwright + Chrome
node game/tests/features/scumm_arcade/floor_runtime_test.cjs
node game/tests/features/scumm_arcade/floor_browser_test.cjs # run after floor_runtime_test
python3 game/tests/features/scumm_arcade/network_test.py
python3 game/tests/features/scumm_arcade/persistence_test.py
node game/tests/features/scumm_arcade/audio_test.cjs # requires a working audio device
```

The runtime test compares independent WASM instances with different batch sizes,
delays and a late replay. The network test runs a real Godot server and two clients,
compares server/client checkpoints, rejects remote/competing control requests, and
checks disconnect handoff. The audio test captures real demo PCM after Godot spatial
mixing: distance falloff, silence at/beyond 5 m, return into range and stereo panning.
Set `GODOT` when it is not on PATH. Headless clients run
the interpreter with `--scumm-runtime`; normal game smoke clients skip it.

## Cabinet model

The bevelled enamel cabinet, brass edge bands, compass side medallions,
buttons, speakers and coin door are an original mesh. Regenerate it with
`blender --background --python game/features/scumm_arcade/model/build_model.py`.
The GLB is checked in; Blender is only needed to edit the model. The live screen
and illuminated lettering are attached by `cabinet_view.gd`, which also applies
each game’s enamel colour and side badge. Each base sits on
the casino’s sunken gaming floor at Y = -1.5.
