# Login and main menu

`login_screen.gd` owns sign-in, account setup, reconnects and the shared in-game
menu. Open it with Esc, controller Start or the touch pause button. Native Esc or
controller B goes back from a submenu, then resumes from the home screen; in a
browser, use Resume to regain mouse capture.

The home screen is the Golden Crown **hotel directory**: the brand line, a "Welcome,
<guest>" line (account name, else the in-world name, else Guest), then icon rows for
Resume, Inventory, Settings, Activities, Players, Account and Quit:
- **Inventory** and **Settings** open their panels directly.
- **Activities** contains GPS, Emotes, Buy guns, Prawn skins, the case journal and any
  future unclassified panel.
- **Players** lists everyone in the session (read locally from the `players` group),
  then Leaderboard and Player stats.
- **Account** contains account actions (Discord link, display name, sign out, leave),
  plus Console, Profiler, Release notes and Quest / WebXR.
- **Quit** quits native builds; online it is **Leave server** (back to offline play).
  Web builds offline have nothing to quit, so the row is hidden.

The brand line and brass rule are ornament and hide below 480 physical pixels wide.
The selected option has a teal focus frame for keyboard and controller.

Features still join `esc_menu_links` and implement `esc_menu_label() -> String`,
`esc_menu_open() -> void` and optionally `esc_menu_icon() -> Texture2D`. Links are
sorted within their section. Classification stays here in `_menu_section()`; no
feature API or networking changes are needed. Opening a feature removes this
screen from `modal_ui` and hands off to that feature's existing modal lifecycle.
Menu navigation is client-local and does not affect other players.

All screens in this owner (including sign-in and account forms) scroll vertically
inside a viewport-bounded panel. Fonts, spacing and 48-pixel button/field targets
compensate for the project's stretched design canvas on small windows (icons
too); resizing or rotating updates the layout. Controller focus scrolls into view.
The shared theme (`ui/theme/ui_theme.tres`) is not mutated. Other feature panels retain their own layouts.

On first load (before the player has ever played), losing input shows a small
**Click to play** prompt (Tap / Press A on touch / controller) over the scene instead
of the full menu; pressing it captures the pointer inside the user gesture. Once the
player has played, a lost pointer lock opens the menu as before.

Authentication, silent reconnection, automatic joining for returning sessions,
and press-time pointer-lock capture are unchanged. No new keys or saved preferences.

Tests: `tests/unit/test_login_screen.gd` and
`tests/features/settings/test_menu_{navigation,layout}.gd`.
