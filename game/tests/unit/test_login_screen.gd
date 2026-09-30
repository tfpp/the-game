extends GutTest
## Login screen behavior (ui/login/login_screen.gd):
## - Skips the sign-in "ready" screen for a returning, already-authenticated player.
## - Idle-menu detection. Regression for #14: opening the chat box also popped the pause
##   menu open on top of it, because both read as "not playing" through
##   Controls.gameplay_active()'s modal_ui check.
## - The Esc menu's links for feature panels (Controls, Release notes) registered via
##   the `esc_menu_links` group.

const Login := preload("res://ui/login/login_screen.gd")


## A stand-in for a feature panel that registers a link in the Esc menu (e.g.
## features/control_scheme/control_scheme.gd, features/changelog/changelog.gd).
class _EscMenuLinkStub:
	extends Node
	var label := "Test panel"
	var opened := false

	func esc_menu_label() -> String:
		return label

	func esc_menu_open() -> void:
		opened = true


func test_auto_plays_when_already_signed_in() -> void:
	assert_true(Login.should_auto_play(true, "", false))


func test_does_not_auto_play_without_being_asked() -> void:
	assert_false(Login.should_auto_play(false, "", false))


func test_does_not_auto_play_with_a_message_to_show() -> void:
	assert_false(Login.should_auto_play(true, "Connection failed.", false))


func test_does_not_auto_play_on_a_version_mismatch() -> void:
	assert_false(Login.should_auto_play(true, "", true))


func test_other_modal_ui_open_is_false_with_nothing_else_open() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	assert_false(menu._other_modal_ui_open())


func test_other_modal_ui_open_is_true_while_the_chat_box_is_open() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	var chat := Node.new()
	add_child_autofree(chat)
	chat.add_to_group(&"modal_ui")
	assert_true(menu._other_modal_ui_open())


## Regression for #20: a dropped connection used to pop the sign-in menu open. Now it
## just schedules a silent retry (see `_attempt_reconnect`), with no menu in between.
func test_connection_failed_does_not_open_the_menu() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._server_url = "ws://example.invalid"
	menu._api = AccountApi.new("")
	add_child_autofree(menu._api)
	menu._on_connection_failed("dropped")
	assert_false(menu.visible)
	assert_false(menu._reconnect_timer.is_stopped())
	assert_almost_eq(menu._reconnect_timer.wait_time, Login.RECONNECT_INTERVAL_S, 0.001)


func test_connection_failed_does_nothing_before_a_server_is_configured() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._on_connection_failed("dropped")
	assert_true(menu._reconnect_timer.is_stopped())


func test_leave_stops_a_pending_reconnect() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._schedule_reconnect()
	menu._leave()
	assert_true(menu._reconnect_timer.is_stopped())


func test_more_menu_adds_a_link_for_each_registered_esc_menu_entry() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	var entry := _EscMenuLinkStub.new()
	entry.label = "Controls"
	add_child_autofree(entry)
	entry.add_to_group(&"esc_menu_links")
	menu._show_menu_section("More")
	var found := false
	for child: Node in menu._box.get_children():
		if child is Button and (child as Button).text == "Controls":
			found = true
	assert_true(found, "expected a Controls link in the Esc menu")


func test_esc_menu_links_are_sorted_alphabetically_by_label() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	var release_notes := _EscMenuLinkStub.new()
	release_notes.label = "Release notes"
	add_child_autofree(release_notes)
	release_notes.add_to_group(&"esc_menu_links")
	var controls := _EscMenuLinkStub.new()
	controls.label = "Controls"
	add_child_autofree(controls)
	controls.add_to_group(&"esc_menu_links")
	menu._show_menu_section("More")
	var labels: Array[String] = []
	for child: Node in menu._box.get_children():
		if child is Button and (child as Button).text in ["Controls", "Release notes"]:
			labels.append((child as Button).text)
	assert_eq(labels, ["Controls", "Release notes"])


func test_opening_an_esc_menu_link_closes_the_menu_and_opens_the_entry() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._show_offline_menu()
	var entry := _EscMenuLinkStub.new()
	add_child_autofree(entry)
	menu._open_esc_menu_link(entry)
	assert_false(menu.visible)
	assert_true(entry.opened)
