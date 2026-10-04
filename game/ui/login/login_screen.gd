extends CanvasLayer
## Sign-in screen shown before joining an online server (`Network.login_required`), and
## the in-game menu. Desktop play uses mouse capture; touch and gamepads use an explicit
## playing state. Losing desktop pointer lock while the window still has focus opens the
## menu (e.g. a browser dropping pointer lock on Esc). Losing focus on the window itself
## (alt-tab, a screenshot tool) just pauses quietly and resumes on its own once focus
## returns (see Controls._focus_regained), so a menu only shows up when explicitly asked
## for. Resume only requests mouse capture for keyboard/mouse input.
##
## Email/password or Discord sign-in, display-name picker, then "Play" fetches a join
## ticket and connects. The offline room keeps running behind it, and "Play offline"
## just closes the screen. Email links and the Discord callback return to the web page
## with a #fragment (verify=, reset=, forgot, discord_code=, auth_error=), handled here.
## A returning player with a valid session skips straight past the "Play" screen and
## connects right away instead of stopping to ask for a click.
## Styled with Kenney's UI Pack (ui/theme/ui_theme.tres).

const MODAL_GROUP := &"modal_ui"
## Feature panels that want an entry here (e.g. Settings, Release notes) join this group
## and implement `esc_menu_label() -> String` and `esc_menu_open() -> void`, and
## optionally `esc_menu_icon() -> Texture2D` (a white icon, tinted by the theme).
const ESC_MENU_LINKS_GROUP := &"esc_menu_links"
const PANEL_WIDTH := 400.0
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const MESSAGE_COLOR := Color(0.3, 0.4, 0.55)
const ERROR_COLOR := Color(0.8, 0.2, 0.2)
const IDLE_MENU_DELAY_S := 0.25
## A dropped connection retries silently at this interval, with no menu in between.
const RECONNECT_INTERVAL_S := 3.0
## The pause menu is styled as the Golden Crown's hotel directory.
const DIRECTORY_TITLE := "Hotel Directory"
const BRAND := "THE GOLDEN CROWN"
## Below this physical width the directory drops its ornament.
const NARROW_PX := 480.0
const ICONS := {
	"Resume": preload("res://assets/kenney/game-icons/PNG/White/1x/forward.png"),
	"Inventory": preload("res://assets/kenney/game-icons/PNG/White/1x/basket.png"),
	"Activities": preload("res://assets/kenney/game-icons/PNG/White/1x/star.png"),
	"Players": preload("res://assets/kenney/game-icons/PNG/White/1x/multiplayer.png"),
	"Account": preload("res://assets/kenney/game-icons/PNG/White/1x/singleplayer.png"),
	"Quit": preload("res://assets/kenney/game-icons/PNG/White/1x/exitRight.png"),
	"Back": preload("res://assets/kenney/game-icons/PNG/White/1x/arrowLeft.png"),
}

const AUTH_ERRORS := {
	"discord_cancelled": "Discord sign-in was cancelled.",
	"discord_expired": "Discord sign-in expired. Try again.",
	"discord_disabled": "Discord sign-in isn't available right now.",
	"discord_in_use": "That Discord account belongs to another player.",
	"discord_already_linked": "This account is already linked to a different Discord account.",
}

var _api: AccountApi
var _account := {}
var _server_url := ""
var _box: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer
var _submenu := false
var _theme: Theme
var _ui_scale := 1.0
## The in-game menu is showing (Esc closes it on native builds).
var _menu_open := false
## How long the mouse has been free with no screen up.
var _idle_s := 0.0
## Fires a silent reconnect attempt after a dropped connection.
var _reconnect_timer: Timer
## Becomes true the first time gameplay is active. Until then, losing input shows the
## small play prompt instead of the full menu, so the first frame shows the Crown.
var _has_played := false
var _play_layer: CanvasLayer
var _play_prompt: Button
## Decorative nodes on the current screen, hidden on narrow screens.
var _ornaments: Array[Control] = []


func _ready() -> void:
	# Above every gameplay HUD layer (combat 20, emote wheel 30) so pause covers all.
	layer = 64
	_build()
	_close()
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)
	Controls.menu_requested.connect(_on_menu_requested)
	Network.login_required.connect(_on_login_required)
	Network.connection_failed.connect(_on_connection_failed)
	if not Network.pending_url.is_empty():
		_on_login_required(Network.pending_url)


func _process(delta: float) -> void:
	if visible and Controls.device == Controls.Device.GAMEPAD:
		_focus_default_button()
	if visible or DisplayServer.get_name() == "headless":
		_idle_s = 0.0
		return
	# The window losing OS focus (alt-tab, a screenshot tool) also reads as "not playing"
	# and can sit that way for a long time; Controls resumes it quietly on its own once
	# focus returns, so don't race it into opening a menu while it's away.
	if not get_window().has_focus():
		_idle_s = 0.0
		return
	# Browsers exit pointer lock on Esc without passing the key on, so watch the mouse
	# mode rather than the key. The grace period covers a lock request still in flight.
	# Another modal (e.g. the chat box) also reads as "not playing" via gameplay_active,
	# but it isn't a lost pointer lock, so don't pop the menu open on top of it.
	if Controls.gameplay_active():
		_has_played = true
	if Controls.gameplay_active() or _other_modal_ui_open():
		_play_layer.visible = false
		_idle_s = 0.0
		return
	_idle_s += delta
	if _idle_s >= IDLE_MENU_DELAY_S:
		_idle_timeout()


## Pointer lock or touch play stopped with no screen up. Before the player has ever
## played, ask for the click (browsers need a gesture) with a small prompt over the
## scene; afterwards a lost lock opens the menu as before.
func _idle_timeout() -> void:
	if _has_played:
		open_menu()
	else:
		_show_play_prompt()


func _show_play_prompt() -> void:
	var verb := "Click"
	if Controls.device == Controls.Device.TOUCH:
		verb = "Tap"
	elif Controls.device == Controls.Device.GAMEPAD:
		verb = "Press A"
	_play_prompt.text = "%s to play" % verb
	_play_layer.visible = true
	if Controls.device == Controls.Device.GAMEPAD and not _play_prompt.has_focus():
		_play_prompt.grab_focus()


func _on_play_prompt_pressed() -> void:
	# Pressing inside the user gesture lets the browser grant pointer lock.
	get_viewport().set_input_as_handled()
	_play_layer.visible = false
	_idle_s = 0.0
	Controls.start()


## True while a different feature owns the modal_ui group (this screen removes itself
## from it whenever it's closed, so any node left is someone else's modal).
func _other_modal_ui_open() -> bool:
	return get_tree().get_first_node_in_group(MODAL_GROUP) != null


func _input(event: InputEvent) -> void:
	if not _menu_open or not visible:
		return
	if not (event.is_action_pressed("release_mouse") or event.is_action_pressed("ui_cancel")):
		return
	# Web Esc cannot re-lock the pointer, but can go Back without starting play.
	# Controller cancel does not need pointer lock and works in web builds too.
	if OS.has_feature("web") and not _submenu and not event is InputEventJoypadButton:
		return
	get_viewport().set_input_as_handled()
	_menu_back()


func _on_menu_requested() -> void:
	if visible:
		if _menu_open:
			_menu_back()
	else:
		open_menu()


## Shows the menu that fits the current state: in game, signed out, or offline only.
func open_menu() -> void:
	_open()
	if Network.mode == Network.Mode.CLIENT:
		_show_game_menu("")
	elif not _server_url.is_empty():
		_resume_session("")
	else:
		_show_offline_menu()


func _on_login_required(url: String) -> void:
	_server_url = url
	if _api == null:
		_api = AccountApi.new(Network.resolve_api_url())
		add_child(_api)
	_open()
	var fragment := _take_fragment()
	if fragment.has("verify"):
		_show_busy("Confirming your email…")
		_finish_sign_in(await _api.verify_email(str(fragment["verify"])))
	elif fragment.has("reset"):
		_show_reset(str(fragment["reset"]))
	elif fragment.has("forgot"):
		_show_forgot()
	elif fragment.has("discord_code"):
		_show_busy("Signing in with Discord…")
		_finish_sign_in(await _api.finish_discord(str(fragment["discord_code"])))
	elif fragment.has("auth_error"):
		var code := str(fragment["auth_error"])
		_resume_session(str(AUTH_ERRORS.get(code, "Discord sign-in failed. Try again.")))
	else:
		_resume_session("", true)


## A dropped connection never shows a menu: it just retries silently (see
## `_attempt_reconnect`) until it's back, or the player leaves or signs out.
func _on_connection_failed(_reason: String) -> void:
	if _server_url.is_empty() or _api == null:
		return
	_schedule_reconnect()


func _schedule_reconnect() -> void:
	_reconnect_timer.start(RECONNECT_INTERVAL_S)


## Silently rejoins with a fresh ticket (the old one's nonce is already spent). A
## failure reaches `_on_connection_failed` again through the usual signal, which
## schedules the next attempt, so this just keeps retrying until it works.
func _attempt_reconnect() -> void:
	if not _api.has_session():
		return
	var result: Dictionary = await _api.join_ticket()
	if result["ok"]:
		Network.join(_server_url, str((result["data"] as Dictionary).get("ticket", "")))
	else:
		_schedule_reconnect()


## Shows "ready to play" if the stored session is still good, else the sign-in form.
## `auto_play` connects immediately instead of waiting for a "Play" click, for the
## normal case of a returning player whose session is still valid.
func _resume_session(message: String, auto_play: bool = false) -> void:
	if not _api.has_session():
		_show_sign_in(message)
		return
	_show_busy("Signing in…")
	var result: Dictionary = await _api.me()
	if result["ok"]:
		_after_sign_in(result["data"], message, auto_play)
	else:
		_show_sign_in(message if message else _error_text(result))


func _finish_sign_in(result: Dictionary) -> void:
	if result["ok"]:
		_after_sign_in((result["data"] as Dictionary).get("account", {}), "")
	else:
		_show_sign_in(_error_text(result))


func _after_sign_in(account: Dictionary, message: String, auto_play: bool = false) -> void:
	_account = account
	if str(account.get("display_name", "")).is_empty():
		_show_pick_name("")
	else:
		_show_ready(message, auto_play)


# Screens.


func _show_sign_in(message: String) -> void:
	_clear("CASINO ROYALE", message)
	_label("Sign in to the Golden Crown")
	var email := _field("Email")
	var password := _field("Password", true)
	var submit := func() -> void:
		_set_busy("Signing in…")
		var result: Dictionary = await _api.log_in(email.text, password.text)
		if result["ok"]:
			_finish_sign_in(result)
		else:
			_set_error(_error_text(result))
	_on_submit(password, submit)
	_button("Sign in", submit)
	if OS.has_feature("web"):
		_button("Sign in with Discord", _start_discord.bind(false))
	_link("Create an account", _show_sign_up)
	_link("Forgot your password?", _show_forgot)
	_game_button("Play offline", _close, false)
	email.grab_focus.call_deferred()


func _show_sign_up() -> void:
	_clear("Create an account", "")
	var email := _field("Email")
	var password := _field("Password (8+ characters)", true)
	var display_name := _field("Display name (3-16 letters, digits, _)")
	var submit := func() -> void:
		_set_busy("Creating your account…")
		var result: Dictionary = await _api.sign_up(email.text, password.text, display_name.text)
		if result["ok"]:
			_show_notice(
				"Check your email", "We sent a link to %s. Open it to finish." % email.text
			)
		else:
			_set_error(_error_text(result))
	_on_submit(display_name, submit)
	_button("Create account", submit)
	_link("Back", _show_sign_in.bind(""))
	email.grab_focus.call_deferred()


func _show_forgot() -> void:
	_clear("Reset your password", "")
	var email := _field("Email")
	var submit := func() -> void:
		_set_busy("Sending…")
		var result: Dictionary = await _api.request_reset(email.text)
		if result["ok"]:
			_show_notice(
				"Check your email", "If %s has an account, a reset link is on its way." % email.text
			)
		else:
			_set_error(_error_text(result))
	_on_submit(email, submit)
	_button("Send reset link", submit)
	_link("Back", _show_sign_in.bind(""))
	email.grab_focus.call_deferred()


func _show_reset(token: String) -> void:
	_clear("Choose a new password", "")
	var password := _field("New password (8+ characters)", true)
	var submit := func() -> void:
		_set_busy("Saving…")
		var result: Dictionary = await _api.confirm_reset(token, password.text)
		if result["ok"]:
			_finish_sign_in(result)
		elif result["error"] == "invalid_password":
			_set_error(_error_text(result))
		else:
			_show_forgot()
			_set_error(_error_text(result))
	_on_submit(password, submit)
	_button("Set password", submit)
	password.grab_focus.call_deferred()


func _show_pick_name(message: String) -> void:
	_clear("Pick a display name", message)
	_label("Other players see this name. 3-16 letters, digits or _.")
	var display_name := _field("Display name")
	var submit := func() -> void:
		_set_busy("Saving…")
		var result: Dictionary = await _api.set_display_name(display_name.text)
		if result["ok"]:
			_account = result["data"]
			if Network.mode == Network.Mode.CLIENT:
				_show_game_menu("Your new name shows up the next time you join.")
			else:
				_show_ready("")
		elif result["status"] == 401:
			_show_sign_in(_error_text(result))
		else:
			_set_error(_error_text(result))
	_on_submit(display_name, submit)
	_button("Save", submit)
	if not str(_account.get("display_name", "")).is_empty():
		_link("Back", _back_to_menu)
	_link("Sign out", _sign_out)
	display_name.grab_focus.call_deferred()


## In-game menu while connected to a server.
func _show_game_menu(message: String) -> void:
	_show_directory(message)


## Menu when no server is configured (native builds default to offline).
func _show_offline_menu() -> void:
	_show_directory("")


## The Golden Crown hotel directory: branding, the guest's name, then one icon row per
## destination. Ornament (brand line, rules, flavor text) hides on narrow screens.
func _show_directory(message: String) -> void:
	_clear(DIRECTORY_TITLE, message, true)
	var guest := _label("Welcome, %s" % guest_name(_account, _local_display_name()))
	guest.name = "Guest"
	guest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ornament(_rule())
	_menu_open = true
	_resume_button()
	_add_menu_sections()
	_resize_panel()


## "MenuTester" for a signed-in account, the in-world name offline, else "Guest".
static func guest_name(account: Dictionary, local_name: String) -> String:
	var account_name := str(account.get("display_name", ""))
	if not account_name.is_empty():
		return account_name
	return local_name if not local_name.is_empty() else "Guest"


func _local_display_name() -> String:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == multiplayer.get_unique_id():
			return player.display_name
	return ""


func _back_to_menu() -> void:
	if Network.mode == Network.Mode.CLIENT:
		_show_game_menu("")
	else:
		_show_ready("")


## True when a returning player should connect immediately instead of being stopped at
## the "Play" screen: they asked to auto-play, there's no error or notice to show, and
## the client isn't stuck behind a version mismatch that needs a page reload first.
static func should_auto_play(auto_play: bool, message: String, version_mismatch: bool) -> bool:
	return auto_play and message.is_empty() and not version_mismatch


## JavaScript that reloads the page with `v=<version>` in the query, keeping the other
## parameters. The new URL bypasses a cached `index.html`, and `shell.html` adds the
## same `v` to the engine's JS, WASM and PCK requests, so the browser fetches the
## server's build instead of looping on the stale cached one (#371).
static func cache_bust_reload_js(version: String) -> String:
	return (
		(
			"(function(){const u=new URL(window.location.href);u.searchParams.set('v',%s);"
			% JSON.stringify(version)
		)
		+ "window.location.replace(u.toString());})()"
	)


func _show_ready(message: String, auto_play: bool = false) -> void:
	var version_mismatch := OS.has_feature("web") and not Network.server_version_mismatch.is_empty()
	if should_auto_play(auto_play, message, version_mismatch):
		if not Controls.needs_pointer_gesture(OS.has_feature("web"), Controls.device):
			Controls.start()
		_play()
		return
	_clear("Signed in as %s" % _account.get("display_name", ""), message)
	_label("Make money. Lose money. Steal it back. Get lucky.")
	if version_mismatch:
		_button(
			"Reload page",
			func() -> void:
				JavaScriptBridge.eval(cache_bust_reload_js(Network.server_version_mismatch))
		)
		_game_button("Play", _play, false)
	else:
		_game_button("Play", _play, true)
	if OS.has_feature("web") and not _account.get("discord_linked", false):
		_link("Link your Discord account", _start_discord.bind(true))
	_link("Change display name", _show_pick_name.bind(""))
	_link("Sign out", _sign_out)
	_game_button("Play offline", _close, false)


func _show_notice(title: String, text: String) -> void:
	_clear(title, "")
	_label(text)
	_link("Back to sign in", _show_sign_in.bind(""))


func _show_busy(text: String) -> void:
	_clear(text, "")


# Actions.


func _play() -> void:
	_show_busy("Joining…")
	var result: Dictionary = await _api.join_ticket()
	if result["ok"]:
		_close()
		Network.join(_server_url, str((result["data"] as Dictionary).get("ticket", "")))
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if result["error"] == "display_name_required":
		_show_pick_name("")
	elif result["status"] == 401:
		_show_sign_in(_error_text(result))
	else:
		_show_ready(_error_text(result))


func _start_discord(link: bool) -> void:
	_show_busy("Opening Discord…")
	var result: Dictionary = await _api.start_discord(link)
	if not result["ok"]:
		_show_sign_in(_error_text(result))
		return
	var url := str((result["data"] as Dictionary).get("url", ""))
	JavaScriptBridge.eval("window.location.assign(%s)" % JSON.stringify(url))


func _resume_button() -> void:
	_game_button("Resume", _close, true).icon = ICONS["Resume"]


## Directory order: Resume, Inventory, Settings, Activities, Players, Account, Quit.
## Inventory and Settings open directly; the rest are one level down.
func _add_menu_sections() -> void:
	_add_esc_menu_links("Inventory")
	_add_esc_menu_links("Settings")
	for section: String in ["Activities", "Players", "Account"]:
		_link(section, _show_menu_section.bind(section)).icon = ICONS[section]
	if Network.mode == Network.Mode.CLIENT:
		_game_button("Leave server", _leave, false).icon = ICONS["Quit"]
	elif not OS.has_feature("web"):
		_link("Quit", get_tree().quit).icon = ICONS["Quit"]


func _show_menu_section(section: String) -> void:
	_clear(section, "")
	_menu_open = true
	_submenu = true
	_link("Back to menu", open_menu).icon = ICONS["Back"]
	if section == "Players":
		_add_guest_list()
	_add_esc_menu_links(section)
	if section == "Account":
		if _api != null and _api.has_session():
			if OS.has_feature("web") and not _account.get("discord_linked", false):
				_link("Link your Discord account", _start_discord.bind(true))
			_link("Change display name", _show_pick_name.bind(""))
			_link("Sign out", _sign_out)
		if Network.mode == Network.Mode.CLIENT:
			_game_button("Leave and play offline", _leave, false)
		elif not OS.has_feature("web"):
			_link("Quit", get_tree().quit)


## Everyone in this session, read from the local `players` group (no networking).
func _add_guest_list() -> void:
	var names := PackedStringArray()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or node.is_queued_for_deletion():
			continue
		var display := player.display_name
		if display.is_empty():
			display = "Player %d" % player.get_multiplayer_authority()
		if player.get_multiplayer_authority() == multiplayer.get_unique_id():
			display += " (you)"
		names.append(display)
	names.sort()
	var heading := _label("In the Crown tonight: %d" % names.size())
	heading.theme_type_variation = &"BrandLabel"
	for display: String in names:
		_label("· " + display).name = "GuestEntry"


func _menu_back() -> void:
	if _submenu:
		open_menu()
	else:
		_resume()


## Unknown/future links land in Activities so they stay reachable.
static func _menu_section(label: String) -> String:
	if label in ["Settings", "Inventory"]:
		return label
	if label in ["Leaderboard", "Player stats"]:
		return "Players"
	if label in ["Console", "Profiler", "Quest / WebXR", "Release notes"]:
		return "Account"
	return "Activities"


## Sorted within each section.
func _add_esc_menu_links(section: String) -> void:
	var entries := get_tree().get_nodes_in_group(ESC_MENU_LINKS_GROUP)
	entries.sort_custom(_esc_menu_label_is_before)
	for entry: Node in entries:
		if _menu_section(entry.esc_menu_label()) != section:
			continue
		var label: String = entry.esc_menu_label()
		var link := _link(label, _open_esc_menu_link.bind(entry))
		if entry.has_method(&"esc_menu_icon"):
			link.icon = entry.esc_menu_icon()
		elif ICONS.has(label):
			link.icon = ICONS[label]


## Closes this menu and hands off to the feature panel's own open/close handling.
func _open_esc_menu_link(entry: Node) -> void:
	_close()
	entry.esc_menu_open()


static func _esc_menu_label_is_before(a: Node, b: Node) -> bool:
	return a.esc_menu_label() < b.esc_menu_label()


## A button that returns to the game: it starts input, then runs `action`. It fires on
## press so the capture happens inside the click, the user gesture browsers require
## for pointer lock. If the lock is refused anyway, the menu comes back.
func _game_button(text: String, action: Callable, primary: bool) -> Button:
	var button := (
		_button(text, _capture_then.bind(action))
		if primary
		else _link(text, _capture_then.bind(action))
	)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	return button


func _capture_then(action: Callable) -> void:
	# Closing the button during its press must not leak that press into gameplay.
	get_viewport().set_input_as_handled()
	Controls.start()
	action.call()


## Closes the menu and resumes the current input device (also native Esc).
func _resume() -> void:
	_close()
	Controls.start()


## Disconnects and keeps playing in the offline room.
func _leave() -> void:
	_reconnect_timer.stop()
	Network.start_offline()
	_close()


func _sign_out() -> void:
	_reconnect_timer.stop()
	if Network.mode == Network.Mode.CLIENT:
		Network.start_offline()
	_show_busy("Signing out…")
	await _api.log_out()
	_account = {}
	_show_sign_in("")


func _open() -> void:
	visible = true
	_play_layer.visible = false
	add_to_group(MODAL_GROUP)
	add_to_group(HudLayout.PAUSE_GROUP)
	Controls.pause()


func _close() -> void:
	visible = false
	_menu_open = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	if is_in_group(HudLayout.PAUSE_GROUP):
		remove_from_group(HudLayout.PAUSE_GROUP)


func _error_text(result: Dictionary) -> String:
	var message := str(result.get("message", ""))
	if message.is_empty():
		return "Something went wrong. Try again."
	return message.left(1).to_upper() + message.substr(1)


## Reads and clears the page's #fragment (web only), e.g. {"verify": "<token>"}.
func _take_fragment() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw: Variant = JavaScriptBridge.eval("window.location.hash")
	var fragment := str(raw).trim_prefix("#") if raw != null else ""
	if fragment.is_empty():
		return {}
	JavaScriptBridge.eval(
		"history.replaceState(null, '', window.location.pathname + window.location.search)"
	)
	var eq := fragment.find("=")
	if eq < 0:
		return {fragment: ""}
	return {fragment.substr(0, eq): fragment.substr(eq + 1).uri_decode()}


# Widgets.


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.08, 0.04, 0.03, 0.62)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_theme = UI_THEME.duplicate()
	backdrop.theme = _theme
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 12)
	_scroll.add_child(_box)
	_build_play_prompt()
	get_viewport().size_changed.connect(_resize_panel)
	_resize_panel()


## Bound the entire form, not just its buttons, so short landscape phones can scroll.
func _resize_panel() -> void:
	if not is_inside_tree():
		return
	# canvas_items stretches a 1280x720 design canvas down on phones. Compensate
	# fonts and hit targets so 48 canvas units still render as at least 48 pixels.
	_ui_scale = clampf(get_viewport().get_stretch_transform().get_scale().x, 0.1, 1.0)
	_theme.default_font_size = roundi(UI_THEME.default_font_size / _ui_scale)
	for type: StringName in UI_THEME.get_type_list():
		for font_size: StringName in UI_THEME.get_font_size_list(type):
			_theme.set_font_size(
				font_size, type, roundi(UI_THEME.get_font_size(font_size, type) / _ui_scale)
			)
	_theme.set_constant(
		"icon_max_width",
		"Button",
		roundi(UI_THEME.get_constant("icon_max_width", "Button") / _ui_scale)
	)
	var available := get_viewport().get_visible_rect().size - Vector2(24, 24) / _ui_scale
	_panel.custom_minimum_size = Vector2(
		minf(PANEL_WIDTH / _ui_scale, maxf(available.x, 0)),
		minf(680 / _ui_scale, maxf(available.y, 0))
	)
	_box.add_theme_constant_override("separation", roundi(12 / _ui_scale))
	var narrow := get_viewport().get_visible_rect().size.x * _ui_scale < NARROW_PX
	for ornament: Control in _ornaments:
		if is_instance_valid(ornament):
			ornament.visible = not narrow
	for child: Node in _box.get_children():
		if child is Button:
			(child as Button).custom_minimum_size.y = 48 / _ui_scale
		elif child is LineEdit:
			(child as LineEdit).custom_minimum_size.y = 48 / _ui_scale


func _clear(title: String, message: String, branded: bool = false) -> void:
	_menu_open = false
	_submenu = false
	_scroll.scroll_vertical = 0
	_ornaments.clear()
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if branded:
		var brand := _label(BRAND)
		brand.name = "Brand"
		brand.theme_type_variation = &"BrandLabel"
		brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ornament(brand)
	var heading := _label(title)
	heading.theme_type_variation = &"HeadingLabel"
	if branded:
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var status := _label(message)
	status.name = "Message"
	status.add_theme_color_override("font_color", ERROR_COLOR)
	status.visible = not message.is_empty()


## Keeps the form but disables it while a request runs.
func _set_busy(text: String) -> void:
	_set_enabled(false)
	_set_message(text, MESSAGE_COLOR)


## Re-enables the form and shows an error above it.
func _set_error(text: String) -> void:
	_set_enabled(true)
	_set_message(text, ERROR_COLOR)


func _set_enabled(enabled: bool) -> void:
	for child: Node in _box.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = not enabled
		elif child is LineEdit:
			(child as LineEdit).editable = enabled


func _set_message(message: String, color: Color) -> void:
	var status := _box.get_node_or_null("Message") as Label
	if status:
		status.text = message
		status.add_theme_color_override("font_color", color)
		status.visible = not message.is_empty()


func _ornament(control: Control) -> Control:
	_ornaments.append(control)
	return control


## A thin brass rule under the directory header.
func _rule() -> HSeparator:
	var rule := HSeparator.new()
	_box.add_child(rule)
	return rule


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(label)
	return label


func _field(placeholder: String, secret: bool = false) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size.y = 48 / _ui_scale
	_box.add_child(edit)
	return edit


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48 / _ui_scale
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(action)
	_box.add_child(button)
	return button


func _link(text: String, action: Callable) -> Button:
	var button := _button(text, action)
	button.theme_type_variation = &"SecondaryButton"
	return button


func _on_submit(edit: LineEdit, action: Callable) -> void:
	edit.text_submitted.connect(func(_text: String) -> void: action.call())


func _focus_default_button() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	for child: Node in _box.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			return


## Small first-load prompt near the bottom of the screen, on its own layer so it shows
## while the menu is hidden. A full-screen transparent button accepts a click anywhere.
func _build_play_prompt() -> void:
	_play_layer = CanvasLayer.new()
	_play_layer.layer = layer
	_play_layer.visible = false
	add_child(_play_layer)
	_play_prompt = Button.new()
	_play_prompt.theme = _theme
	_play_prompt.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_play_prompt.flat = true
	_play_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_play_prompt.add_theme_font_size_override("font_size", 28)
	_play_prompt.add_theme_color_override("font_color", Color.WHITE)
	_play_prompt.add_theme_color_override("font_hover_color", Color(1, 0.85, 0.4))
	_play_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_play_prompt.add_theme_constant_override("outline_size", 8)
	_play_prompt.pressed.connect(_on_play_prompt_pressed)
	_play_layer.add_child(_play_prompt)
