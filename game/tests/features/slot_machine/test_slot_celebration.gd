extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")
var _machine: SlotMachine
var _fx: SlotCelebration


func before_each() -> void:
	_machine = MACHINE.instantiate() as SlotMachine
	add_child_autofree(_machine)
	_machine.set_process(false)
	_fx = _machine.get_node("Celebration") as SlotCelebration


func _count(type_name: String) -> int:
	var total := 0
	for child: Node in _fx.get_children():
		if child.name.begins_with(type_name) and (child as Node3D).visible:
			total += 1
	return total


func test_effects_grow_with_the_prize() -> void:
	var small := 1000  # $10: the $1 machine's smallest win
	var big := 3_000_000_000_000  # $30B: the $1B machine's 7-7-7
	assert_eq(SlotCelebration.intensity(small), 0.0)
	assert_almost_eq(SlotCelebration.intensity(big), 1.0, 0.01)
	assert_lt(SlotCelebration.rocket_count(small), SlotCelebration.rocket_count(big))
	assert_lt(SlotCelebration.sparks_per_rocket(small), SlotCelebration.sparks_per_rocket(big))
	assert_lt(SlotCelebration.burst_speed(small), SlotCelebration.burst_speed(big))
	assert_lt(SlotCelebration.coin_count(small), SlotCelebration.coin_count(big))
	assert_lt(SlotCelebration.coin_count(100_000), SlotCelebration.coin_count(10_000_000))


func test_win_result_launches_shells_and_coins() -> void:
	_machine.play_result(1, true, 3_000_000_000_000)
	assert_eq(_count("Coins"), 1)
	assert_eq(_fx._targets.size(), SlotCelebration.rocket_count(3_000_000_000_000))
	assert_eq(_count("Shell"), 1, "Shells launch on their staggered schedule")
	var coins := _fx.get_node("Coins") as CPUParticles3D
	assert_true(coins.emitting)
	assert_gt(coins.direction.z, 0.0, "Coins fly out the front of the cabinet")


func test_loss_and_replayed_results_do_nothing() -> void:
	_machine.play_result(1, false, 0)
	assert_eq(_count("Coins"), 0)
	assert_false(_fx.is_processing())
	_machine.play_result(2, true, 1000)
	var after_win := _fx.get_child_count()
	_machine.play_result(2, true, 1000)
	assert_eq(_fx.get_child_count(), after_win, "A repeated event does not relaunch")


func test_shells_burst_into_sparks() -> void:
	_fx.celebrate(1000)
	_fx._process(0.61)
	var burst := _fx.get_node("Burst0") as CPUParticles3D
	assert_eq(burst.amount, SlotCelebration.sparks_per_rocket(1000))
	assert_true(burst.one_shot)
	assert_true(burst.emitting)


func test_pool_reuses_nodes_meshes_and_materials_and_clears_scheduled_bursts() -> void:
	var coins := _fx.get_node("Coins") as CPUParticles3D
	var burst := _fx.get_node("Burst0") as CPUParticles3D
	var mesh := burst.mesh
	var material := mesh.surface_get_material(0)
	var children := _fx.get_children()
	_fx.celebrate(3_000_000_000_000)
	_fx._process(0.7)
	_fx.clear()
	assert_false(_fx.is_processing())
	assert_eq(_fx._targets.size(), 0)
	assert_false(burst.visible)
	assert_false(coins.visible)
	_fx.celebrate(1000)
	_fx._process(0.7)
	assert_eq(_fx.get_children(), children)
	assert_same(burst.mesh, mesh)
	assert_same(burst.mesh.surface_get_material(0), material)
	assert_eq(_fx._launched, 1)
	_fx._process(5.0)
	assert_false(_fx.is_processing())


func test_far_away_camera_skips_cosmetic_work() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(100, 0, 0)
	add_child_autofree(camera)
	camera.make_current()
	_fx.celebrate(1000)
	assert_false(_fx.is_processing())
	assert_eq(_fx._targets.size(), 0)
