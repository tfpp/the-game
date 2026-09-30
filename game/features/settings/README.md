# Settings

`settings.gd` registers the direct **Settings** link on the main menu. It owns the
existing settings hub, page navigation and modal lifecycle; `settings_store.gd`
persists local player preferences. Main-menu grouping and responsive login/menu
layout belong to `ui/login/login_screen.gd`, documented in `ui/login/README.md`.

Pages join `settings_pages` and implement `settings_page_label() -> String` and
`settings_page_build() -> Control`, optionally `settings_page_icon() -> Texture2D`
and `settings_page_input(event: InputEvent) -> bool`. Fresh content is freed when
leaving the page. Esc/controller B steps back to the hub, then to the main menu.
Use `SettingsStore` for persistent preferences; shared gameplay settings keep
server authority in their own feature.

Run the GUT tests in `tests/features/settings/` for settings persistence/page
navigation and main-menu handoff, grouping, small-screen layout and input checks.
