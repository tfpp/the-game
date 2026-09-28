extends GutTest
## Coverage for the Gun-O-Matic's detailed look: every generated gun carries the
## requested parts (stock, grip, sights, rails, trigger), and the cabinet assembles a
## sold gun part by part before going back to its demo gun.

const KioskScene := preload("res://features/gun_machine/kiosk.tscn")


func _stats(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GunGenerator.generate(rng)


func test_every_gun_has_stock_grip_sights_rails_and_trigger() -> void:
	for seed_value: int in 40:
		var gun := GunView.build(_stats(seed_value))
		for part: StringName in GunView.PART_NAMES:
			var node := gun.get_node_or_null(NodePath(String(part)))
			assert_not_null(node, "seed %d missing %s" % [seed_value, part])
			if node != null:
				assert_gt(node.get_child_count(), 0, "%s has geometry" % part)
		assert_not_null(gun.get_node_or_null(^"Muzzle"))
		gun.free()


func test_barrel_count_still_matches_stats() -> void:
	for seed_value: int in 40:
		var stats := _stats(seed_value)
		var gun := GunView.build(stats)
		# One barrel plus one muzzle ring per rolled barrel.
		assert_eq(gun.get_node(^"Barrels").get_child_count(), int(stats["barrel_count"]) * 2)
		gun.free()


func test_parts_visible_reveals_gradually() -> void:
	var count := GunView.PART_NAMES.size()
	assert_eq(GunMachineCabinet.parts_visible(0.0, count), 1)
	assert_eq(GunMachineCabinet.parts_visible(GunMachineCabinet.ASSEMBLY_DURATION, count), count)
	assert_eq(GunMachineCabinet.parts_visible(-1.0, count), count)
	var half := GunMachineCabinet.parts_visible(GunMachineCabinet.ASSEMBLY_DURATION * 0.5, count)
	assert_between(half, 2, count - 1)


func test_kiosk_builds_a_detailed_machine_and_assembles_a_sold_gun() -> void:
	var kiosk := KioskScene.instantiate() as GunMachineKiosk
	add_child_autofree(kiosk)
	var cabinet := kiosk.get_node(^"Cabinet") as GunMachineCabinet
	for part: String in ["Glass", "Tray", "Mill", "Arm", "Gantry", "BuyButton"]:
		assert_not_null(cabinet.get_node_or_null(NodePath(part)), part)
	assert_not_null(cabinet.bench_gun(), "idles with a demo gun")
	assert_false(cabinet.is_assembling())

	kiosk.play_assembly(_stats(3))
	assert_true(cabinet.is_assembling())
	var gun := cabinet.bench_gun()
	assert_false((gun.get_node(^"Receiver") as Node3D).visible, "starts from nothing")
	cabinet._process(0.01)
	assert_true((gun.get_node(^"Receiver") as Node3D).visible)
	assert_false((gun.get_node(^"FrontSight") as Node3D).visible, "sights come last")

	cabinet._process(GunMachineCabinet.ASSEMBLY_DURATION)
	assert_true((gun.get_node(^"FrontSight") as Node3D).visible)
	cabinet._process(GunMachineCabinet.SHOWCASE_DURATION)
	assert_false(cabinet.is_assembling(), "returns to idle")
