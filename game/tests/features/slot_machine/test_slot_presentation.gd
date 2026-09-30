extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")
var _machine: SlotMachine
var _view: Node3D


func before_each() -> void:
	_machine = MACHINE.instantiate() as SlotMachine
	add_child_autofree(_machine)
	_machine.set_process(false)
	_view = _machine.get_node("View")
	_view.set_process(false)


func test_late_join_stopped_reels_immediately_show_authoritative_symbols() -> void:
	_machine.state = _snapshot(false, 3, [4, 2, 1])
	_view._process(0.016)
	assert_eq(_view._positions, [4.0, 2.0, 1.0])
	assert_eq(_view._status.text, "WON $30.00")


func test_stop_order_settles_correct_symbols_while_remaining_reels_keep_moving() -> void:
	_machine.state = _snapshot(true, 0, [0, 1, 2])
	_view._process(0.02)
	_machine.state = _snapshot(true, 1, [4, 1, 2])
	_view._process(0.2)
	assert_almost_eq(fposmod(_view._positions[0], 5.0), 4.0, 0.001)
	var moving: float = _view._positions[1]
	_view._process(0.02)
	assert_ne(_view._positions[1], moving)
	assert_almost_eq(fposmod(_view._positions[0], 5.0), 4.0, 0.001)
	_machine.state = _snapshot(false, 3, [4, 4, 4])
	_view._process(0.2)
	for index: int in 3:
		assert_almost_eq(fposmod(_view._positions[index], 5.0), 4.0, 0.001)
		assert_eq(_machine.state["reels"][index], 4, "Presentation never mutates results")


func test_large_prices_and_server_messages_fit_real_display_widths() -> void:
	_machine.buy_in_cents = 100000000000
	_machine.state = _snapshot(false, 3, [0, 0, 0])
	_machine.state["message"] = "Unable to complete payment. Please try again."
	_view._process(0.016)
	var caption: Label3D = _view._caption
	var status: Label3D = _view._status
	assert_string_contains(caption.text, "1,000,000,000.00")
	for label: Label3D in [caption, status]:
		var width := (
			(
				ThemeDB
				. fallback_font
				. get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
				. x
			)
			* label.pixel_size
		)
		assert_lte(width, 1.69 if label == caption else 1.19)


func _snapshot(spinning: bool, stopped: int, reels: Array) -> Dictionary:
	return {
		"spin": 1,
		"spinning": spinning,
		"stopped": stopped,
		"reels": reels,
		"won": true,
		"payout": 3000,
		"operator": "Player",
		"message": ""
	}
