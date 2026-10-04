extends GutTest
## Controlled firing exercises on the actual map, with enemy AI and weapon timing.
## Repositioning between encounters is scripted; this is not a manual playtest.

const ZONES := preload("res://features/zone_instances/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")


func _clear_floor(depth: int, weapon: String) -> Dictionary:
	seed(73021)
	var root := Node3D.new()
	add_child_autofree(root)
	var zones := ZONES.instantiate() as ZoneInstances
	root.add_child(zones)
	var combat := COMBAT.instantiate() as Combat
	root.add_child(combat)
	var died := [false]
	combat.player_died.connect(
		func(victim: int, _attacker: int) -> void:
			if victim == 1:
				died[0] = true
	)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	root.add_child(hand)
	hand.net_item_id = weapon
	var pack := "ammo:%s:%d" % [weapon, int(ItemCatalog.AMMO_PACKS[weapon]["rounds"])]
	hand.inventory().collect(pack)
	hand.inventory().collect(pack)
	var magazine := hand.magazine_for(weapon)
	magazine.advance(0.0)
	var marker := Marker3D.new()
	root.add_child(marker)
	var run := zones.create_excursion(
		[1] as Array[int], marker, SlumInstance.Destination.GARAGE, 73021
	)
	var shots := [0]
	hand.fired.connect(func(_id: String) -> void: shots[0] += 1)
	var reloads := 0
	var start_frame := Engine.get_physics_frames()
	var cleared := 0
	for node: Node in run.get_node("Map/CrownGarage/Enemies").get_children():
		var enemy := node as GarageEnemy
		if not is_equal_approx(enemy.home().y, 16.0 - depth * 4.0):
			continue
		var direction := -1.0 if enemy.home().z > 20.0 else 1.0
		player.global_position = run.to_global(enemy.home() + Vector3(0, .95, direction * 6))
		player.net_position = player.global_position
		await wait_physics_frames(2)
		if died[0]:
			break
		var encounter_frames := 0
		while enemy.net_alive and encounter_frames < 640 and not died[0]:
			var aim := (enemy.global_position + Vector3.UP - hand._aim_origin(player)).normalized()
			player.net_yaw = atan2(-aim.x, -aim.z)
			player.net_pitch = asin(aim.y)
			if magazine.loaded() == 0 and not magazine.active():
				magazine.entity._evaluate(1, &"reload", {})
				reloads += 1
			hand.request_primary_action()
			await wait_physics_frames(1)
			encounter_frames += 1
		if not enemy.net_alive:
			cleared += 1
		if died[0]:
			break
	var result := {
		"floor": depth + 1,
		"weapon": weapon,
		"cleared": cleared,
		"shots": shots[0],
		"reloads": reloads,
		"seconds": (Engine.get_physics_frames() - start_frame) / 64.0,
		"health": 0.0 if died[0] else combat.health_for(1),
		"died": died[0]
	}
	print("GARAGE_WEAPON_PRESSURE ", JSON.stringify(result))
	root.free()
	return result


func test_top_floor_clears_with_one_pistol_magazine() -> void:
	var result := await _clear_floor(0, "pistol")
	assert_eq(result["cleared"], 2)
	assert_eq(result["reloads"], 0)
	assert_lte(result["shots"], 7)
	assert_gt(result["health"], 0.0)
	assert_false(result["died"])


func test_bottom_floor_exposes_pistol_reload_pressure_and_rifle_advantage() -> void:
	var pistol := await _clear_floor(4, "pistol")
	var rifle := await _clear_floor(4, "m4a4")
	assert_eq(rifle["cleared"], 6)
	assert_eq(rifle["reloads"], 0)
	assert_gt(pistol["reloads"], 0)
	assert_lt(rifle["seconds"], pistol["seconds"])
	assert_gt(rifle["health"], pistol["health"], "Faster firing avoids reload exposure")
	assert_true(pistol["died"], "An exposed pistol run cannot clear the deepest encounter")
	assert_lt(pistol["cleared"], 6)
	assert_false(rifle["died"], "Stronger equipment can clear B5")
