extends GutTest
## Exercise the public Use picker rather than directly calling shift.act().

const BAR := preload("res://features/bar_companion/feature.tscn")
const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const INTERACTION := preload("res://features/interaction/interaction.gd")
var _shift: BusboyShift
var _player: Player
var _use: CanvasLayer
var _device: Controls.Device


func before_each() -> void:
	add_child_autofree(ROOM.instantiate())
	var bar := BAR.instantiate() as Node3D
	add_child_autofree(bar)
	_shift = bar.get_node("BusboyShift") as BusboyShift
	_shift.set_process(false)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_use = INTERACTION.new()
	add_child_autofree(_use)
	_device = Controls.device
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	for point: Node3D in _shift._points:
		var talk := point.get_node("NetworkedEntity") as NetworkedInteraction
		talk._actions[&"use"].cooldown_msec = 0


func after_each() -> void:
	Controls.pause()
	Controls.select_device(_device)


func _stand(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at


func test_shared_use_starts_with_visible_work_and_returns_glass_from_standing_height() -> void:
	_stand(Vector3(-10, -0.35, -8.65))
	assert_string_contains(_use.target_text(), "Start busboy")
	_use.use()
	assert_eq(_shift.phase, "active")
	assert_eq(_shift.dirty, [0])
	_shift._present()
	assert_true(_shift.get_node("Glass0").visible)
	assert_string_contains(_shift.get_node("Glass0/Label").text, "table 1")
	assert_eq(_use.target_text(), "", "no misleading counter action while empty-handed")
	_stand(Vector3(-8.2, -0.35, -5.9))
	assert_string_contains(_use.target_text(), "empty glass from table 1")
	_use.use()
	assert_eq(_shift.cargo, -2)
	_stand(Vector3(-10, -0.35, -8.65))
	assert_eq(_use.target_text(), "Drop off empty glass")
	_use.use()
	assert_eq(_shift.cleared, 1)
	assert_eq(_shift.cargo, -1)


func test_shared_use_collects_from_existing_west_and_three_new_tables() -> void:
	_stand(Vector3(-10, -0.35, -8.65))
	_use.use()
	for table: int in range(4, 8):
		_shift.dirty = [table * 3]
		_shift._publish()
		_shift._present()
		_stand(BusboyShift.TABLES[table] + Vector3(0, -0.145, -1.0))
		assert_string_contains(_use.target_text(), "table %d" % (table + 1))
		_use.use()
		assert_eq(_shift.cargo, -2)
		assert_true(_shift.dirty.is_empty())
		_stand(Vector3(-10, -0.35, -8.65))
		_use.use()
	assert_eq(_shift.cleared, 4)
