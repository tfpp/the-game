extends GutTest

var book: ChickenBettingBook
var menu: ChickenBettingMenu


func before_each() -> void:
	var feature := preload("res://features/chicken_betting/feature.tscn").instantiate() as Node3D
	add_child_autofree(feature)
	book = feature.get_node("Room/Book") as ChickenBettingBook
	book.set_process(false)
	book.config = ChickenFightConfig.new()
	book.config.odds_samples = 64
	book._prepare()
	menu = ChickenBettingMenu.new()
	menu.book = book
	add_child_autofree(menu)
	menu._process(0)


func after_each() -> void:
	Controls.start()


func test_form_has_modal_contract_stats_odds_and_configured_decimal_limits() -> void:
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_true(menu._stats.text.contains("Strength"))
	assert_true(menu._stats.text.contains("Luck"))
	assert_true(menu._stats.text.contains("return"))
	assert_eq(menu._stake.min_value, 1.0)
	assert_eq(menu._stake.max_value, 100.0)
	assert_eq(menu._stake.step, 0.01)
	assert_false(menu._place.disabled)
	menu.close()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_true(Controls.playing, "close restores gameplay intent even on headless keyboard")


func test_form_disables_tickets_while_fighting_and_shows_knockout_winner() -> void:
	var next := book.state.duplicate(true)
	next["phase"] = "result"
	next["winner"] = 1
	next["health"] = [0, 30]
	book.state = next
	menu._process(0)
	assert_true(menu._place.disabled)
	assert_true(menu._stats.text.contains("Winner: " + str(book.state["birds"][1]["name"])))
	assert_true(menu._stats.text.contains("HP 0"))
