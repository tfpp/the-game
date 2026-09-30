# Login and main menu

`login_screen.gd` owns sign-in, account setup, reconnects and the shared in-game
menu. Open it with Esc, controller Start or the touch pause button. Native Esc or
controller B goes back from a submenu, then resumes from the home screen; in a
browser, use Resume to regain mouse capture.

The home screen has Resume, Settings, Activities and More:
- **Settings** opens the existing settings hub directly.
- **Activities** contains GPS, Inventory and Leaderboard.
- **More** contains Console, Profiler, Release notes, Quest / WebXR and any future
  unclassified panel, plus account/session actions when applicable and native Quit.

Features still join `esc_menu_links` and implement `esc_menu_label() -> String`,
`esc_menu_open() -> void` and optionally `esc_menu_icon() -> Texture2D`. Links are
sorted within their section. Classification stays here in `_menu_section()`; no
feature API or networking changes are needed. Opening a feature removes this
screen from `modal_ui` and hands off to that feature's existing modal lifecycle.
Menu navigation is client-local and does not affect other players.

All screens in this owner (including sign-in and account forms) scroll vertically
inside a viewport-bounded panel. Fonts, spacing and 48-pixel button/field targets
compensate for the project's stretched design canvas on small windows; resizing
or rotating updates the layout. Controller focus scrolls into view. The shared
Kenney theme is not mutated. Other feature panels retain their own layouts.

Authentication, silent reconnection, automatic joining for returning sessions,
and press-time pointer-lock capture are unchanged. No new keys or saved preferences.

Tests: `tests/unit/test_login_screen.gd` and
`tests/features/settings/test_menu_{navigation,layout}.gd`.
