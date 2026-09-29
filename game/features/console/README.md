# Console

Press **~ / backtick** (the key below Esc on a US keyboard), or open **Esc → Console**.
The olive-grey Source-style panel pauses gameplay input. Close with the same key,
Esc, controller B, or Close. Browser pointer-lock rules may show the Resume menu
when closing with Esc; Close is a user gesture that can recapture the mouse.
Touch users can open it from the menu, use their software keyboard and tap Tab/Run.
Controllers can open it from the menu and activate suggestions, but free-form text
requires a keyboard. No controller button is claimed by default; Controls can rebind it.

Type a command alone to inspect its value, or append a value to change it. `help`
lists every command and range; `help frog` filters help. Matching ignores command
case, ranks prefixes before substrings, and suggests boolean values, handedness,
action names and common keys/mouse/controller buttons. Up/Down select suggestions,
Tab (or double-click/tap) completes. Up on an empty line recalls history;
Ctrl+Up/Down recalls it while editing. Output and history are bounded and session-local.

Examples:

```
sensitivity 2.5
volume 0.6
scheme right
bind jump Space
bind primary_action mouse:1
bind jump pad:0
jump_height_scale 1.5
sv_cheats 1
noclip
```

`commands.gd` adapts all current Settings menu options: Audio (overall/effects/mute),
Controls (handedness, three sensitivities, bindings/reset), and Game (three scales).
It calls their existing public setters/RPCs; preferences retain their existing
SettingsStore persistence and shared settings retain their server ownership. It
accepts a fixed command catalog, finite numbers and validated key names, never
arbitrary engine properties, scripts, filesystem paths or shell commands. “Any
setting” means player-facing settings, not Godot project configuration or secrets.

`sv_cheats` and flight belong to `features/noclip`; console owns no shared state.
Shared settings and cheats can be changed by any connected player, as with the
existing Game page. Requests show as requested until the server state arrives;
query again to read the authoritative value. World settings reset per server session.

Tests: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/console -gexit`.

## Read-only Git

Type `git help` for the fixed command list. `git log` (or `git log --oneline`)
shows the last 20 subjects; `git show` (or `git show --stat`) shows HEAD's subject
and file statistics, never a patch. `git status` shows tracked changes at snapshot
time, `git branch` the current branch (or detached HEAD), `git rev-parse HEAD`
the commit, and `git ls-files` tracked paths. All other arguments are rejected,
including revision/path arguments, Git options, writes and shell syntax.

This is an explicitly labelled **build-time snapshot**, not a live server checkout.
`game/scripts/export.sh` runs `scripts/git_snapshot.gd` in Godot to bundle a generated
GDScript resource, then cleans it up. Git is a build tool only; exports
do not need it and work offline. Native editor runs lazily run that same collector
once per console instance. Direct exports bypassing the script show an unavailable
message. Queries are fixed, use no shell, suppress optional locks and filesystem
monitor hooks, and only collect metadata (no source contents, config or remotes).
Each result is capped at 12,000 characters; shallow builds show available history.
Local output needs no RPC or persistence and does not change shared game state.
