extends GutTest

const FEATURE := preload("res://features/bar_companion/feature.tscn")
const MENU := preload("res://features/bar_companion/stats_menu.gd")
var _bar: BarCompanion
var _menu: CanvasLayer


func before_each() -> void:
	Network.peer_accounts.clear()
	_bar = FEATURE.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_menu = _bar.get_node("StatsMenu")


func after_each() -> void:
	_menu._close(false)
	Controls.pause()


func test_menu_shows_zero_stats_and_obeys_modal_lifecycle() -> void:
	assert_true(_menu.is_in_group(&"esc_menu_links"))
	assert_eq(_menu.esc_menu_label(), "Player stats")
	_menu.esc_menu_open()
	assert_true(_menu.is_in_group(&"modal_ui"))
	assert_string_contains(_menu._label.text, "Charisma: 0 / 10")
	assert_string_contains(_menu._label.text, "Intoxication: 0 / 10 (sober)")
	assert_true(_menu._close_button.has_focus())
	_menu._close(false)
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_false(_menu._root.visible)


func test_live_refresh_reads_replicated_stats_without_mutation() -> void:
	_menu.esc_menu_open()
	_bar.stats = {1: [1, 4, 125]}
	_menu._process(0.0)
	assert_string_contains(_menu._label.text, "Debuff: too drunk")
	assert_string_contains(_menu._label.text, "2:05")
	assert_true(_bar._state.is_empty())
	Network.mode_changed.emit(Network.Mode.OFFLINE)
	assert_false(_menu._root.visible)
	assert_false(_menu.is_in_group(&"modal_ui"))


func test_description_explains_buffs_and_existing_blessings() -> void:
	var text: String = MENU.describe(3, 3, 0, 2)
	assert_string_contains(text, "Buff: tipsy")
	assert_string_contains(text, "$39.50")
	assert_string_contains(text, "Lucky night: inactive")
	assert_string_contains(text, "Kaaba blessings: 2 / 5 (+400%")
	assert_string_contains(text, "signed out")
