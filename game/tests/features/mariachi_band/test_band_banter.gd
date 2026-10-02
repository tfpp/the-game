extends GutTest
## Session-owned physique, backstage whispers, hitboxes and respawns.

const FEATURE := preload("res://features/mariachi_band/feature.tscn")

var _band: MariachiBand


func before_each() -> void:
	_band = FEATURE.instantiate() as MariachiBand
	add_child_autofree(_band)
	_band.set_process(false)
	await wait_process_frames(2)


func _musician(index: int) -> StationaryPatron:
	return _band.get_node("Musicians").get_child(index) as StationaryPatron


func test_server_randomly_selects_exactly_one_member_and_keeps_selection() -> void:
	assert_between(_band.net_stocky_member, 0, 4)
	var chosen := _band.net_stocky_member
	_band.advance()
	assert_eq(_band.net_stocky_member, chosen, "song requests do not reroll the member")
	var seen: Dictionary[int, bool] = {}
	_band._rng.seed = 399
	for attempt: int in 50:
		_band._reset_session(Network.Mode.OFFLINE)
		seen[_band.net_stocky_member] = true
		var stocky_count := 0
		for index: int in 5:
			var body := _musician(index).get_node("Body") as MariachiMusicianModel
			if body.scale == MariachiBand.STOCKY_SCALE:
				stocky_count += 1
			else:
				assert_eq(body.scale, Vector3.ONE)
		assert_eq(stocky_count, 1, "never zero or multiple stocky musicians")
	assert_eq(seen.size(), 5, "every member can be selected")


func test_every_variant_keeps_feet_hitbox_and_instrument_grips_aligned() -> void:
	for chosen: int in 5:
		_band.net_stocky_member = chosen
		for phase: int in 3:
			_band.net_banter = phase
			for index: int in 5:
				var musician := _musician(index)
				var body := musician.get_node("Body") as MariachiMusicianModel
				body._update(0.1)
				assert_eq(body.position, Vector3.ZERO, "scale anchored at the feet")
				var hitbox := musician.get_node("Hitbox") as CollisionShape3D
				var bounds := body.transform * body.hitbox_bounds()
				assert_almost_eq(hitbox.position.y, bounds.get_center().y, 0.0001)
				assert_almost_eq((hitbox.shape as BoxShape3D).size.y, bounds.size.y, 0.0001)
				assert_almost_eq(hitbox.position.z, bounds.get_center().z, 0.0001)
				assert_almost_eq((hitbox.shape as BoxShape3D).size.x, bounds.size.x, 0.0001)
				assert_almost_eq(bounds.position.y, 0.0, 0.0001, "hitbox starts at stage")
				for right: bool in [true, false]:
					var shoulder := body.bone_position("UpperArmR" if right else "UpperArmL")
					var local_hand := body.to_local(body.hand_position(right))
					assert_lt(local_hand.distance_to(body.to_local(shoulder)), 0.7)
				var mesh_bounds := StationaryPatron._model_bounds(body, Transform3D.IDENTITY)
				assert_lt(mesh_bounds.end.z + musician.position.z, 1.15, "backdrop clear")
				# The posed hitbox footprint, not the skinned mesh's conservative rest AABB.
				for x: float in [bounds.position.x, bounds.end.x]:
					for z: float in [bounds.position.z, bounds.end.z]:
						var point := musician.position + Vector3(x, 0, z)
						assert_lt(Vector2(point.x, point.z).length(), 2.6, "stage rim clear")
				# All instrument grips transform with the same scaled rig.
				if body.instrument == MariachiMusicianModel.Instrument.TRUMPET:
					var grip := body._horn.global_transform * Vector3(0.03, 0.035, -0.12)
					assert_lt(body.hand_position(true).distance_to(grip), 0.08)


func test_server_schedules_two_whispers_while_target_faces_backstage() -> void:
	_band.net_stocky_member = 0
	_band._process(11.9)
	assert_eq(_band.net_banter, 0)
	_band._process(0.2)
	assert_eq(_band.net_banter, 1)
	var target := _musician(0).get_node("Body") as Node3D
	assert_gt((target.basis * Vector3.FORWARD).dot(Vector3.BACK), 0.99)
	var first := _musician(1).get_node("Whisper") as Label3D
	assert_true(first.visible)
	assert_eq(first.text, MariachiBand.BANTER_LINES[0])
	assert_false((_musician(0).get_node("Whisper") as Label3D).visible)
	_band._process(4.0)
	assert_eq(_band.net_banter, 2)
	assert_false(first.visible)
	assert_true((_musician(2).get_node("Whisper") as Label3D).visible)
	_band._process(4.0)
	assert_eq(_band.net_banter, 0)
	assert_gt((target.basis * Vector3.FORWARD).dot(Vector3.FORWARD), 0.99)
	assert_false((_musician(2).get_node("Whisper") as Label3D).visible)
	assert_eq(MariachiBand.banter_phase(48.0), 1, "repeats after quiet interval")


func test_deaths_hide_whispers_and_respawns_keep_the_selected_build() -> void:
	_band.net_stocky_member = 4
	_band.net_banter = 1
	var speaker := _musician(0)
	var bubble := speaker.get_node("Whisper") as Label3D
	assert_true(bubble.visible)
	speaker.take_hit(1)
	_band._process(0.0)
	assert_false(bubble.visible)
	speaker._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	_band.net_banter = 1
	assert_true(bubble.visible)
	_musician(4).take_hit(1)
	_band._process(0.0)
	assert_false(bubble.visible, "no joke while he is absent")
	_musician(4)._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	assert_eq(_band.net_stocky_member, 4)
	assert_eq((_musician(4).get_node("Body") as Node3D).scale, MariachiBand.STOCKY_SCALE)
	_band._reset_session(Network.Mode.OFFLINE)
	assert_eq(_band.net_banter, 0)
	assert_false(bubble.visible)


func test_snapshot_presents_physique_turn_and_current_whisper() -> void:
	var late := FEATURE.instantiate() as MariachiBand
	late.net_stocky_member = 3
	late.net_banter = 2
	add_child_autofree(late)
	late.set_process(false)
	await wait_process_frames(1)
	var target := late.get_node("Musicians/SecondTrumpet/Body") as Node3D
	assert_eq(target.scale, MariachiBand.STOCKY_SCALE)
	assert_gt((target.basis * Vector3.FORWARD).dot(Vector3.BACK), 0.99)
	var bubble := late.get_node("Musicians/GuitarronPlayer/Whisper") as Label3D
	assert_true(bubble.visible)
	assert_eq(bubble.text, MariachiBand.BANTER_LINES[1])
	var sync := late.get_node("NetworkedEntity/Sync") as MultiplayerSynchronizer
	for property: NodePath in [NodePath(".:net_stocky_member"), NodePath(".:net_banter")]:
		assert_true(sync.replication_config.has_property(property))
		assert_true(sync.replication_config.property_get_spawn(property))
