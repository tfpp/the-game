extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")

var _audio: GameAudio
var _player: Player
var _hand: Hand
var _events: Array[Dictionary] = []


func before_each() -> void:
	_events.clear()
	_audio = GameAudio.new()
	add_child_autofree(_audio)
	_audio.sound_started.connect(_on_sound)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func _on_sound(cue: StringName, positional: bool, at: Vector3) -> void:
	_events.append({"cue": cue, "positional": positional, "at": at})


func test_accepted_shot_plays_once_and_cooldown_rejects_extra_audio() -> void:
	_hand.net_item_id = "smg"
	_hand.inventory().collect("ammo:smg:1")
	_events.clear()
	_hand.request_primary_action()
	_hand.request_primary_action()
	assert_eq(_events.size(), 1)
	assert_eq(_events[0].cue, &"smg")
	assert_true(_events[0].positional)
	assert_eq(_events[0].at, _hand._aim_origin(_player))


func test_sound_uses_event_weapon_even_after_equipment_changes() -> void:
	_hand.net_item_id = "banana"
	_hand._play_fire("awp", Vector3(5, 2, 3))
	assert_eq(_events[0].cue, &"awp")
	assert_eq(_events[0].at, Vector3(5, 2, 3))


func test_shotgun_surface_impact_plays_once_at_hit_position() -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 10, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position.z = -3.0
	add_child_autofree(wall)
	await wait_physics_frames(2)
	_hand.net_item_id = "shotgun"
	_hand.inventory().collect("ammo:shotgun:1")
	_events.clear()
	_hand.request_primary_action()
	assert_eq(_events.size(), 2, "One report and one impact, not eight copies per pellet")
	assert_eq(_events[1].cue, &"impact")
	assert_almost_eq((_events[1].at as Vector3).z, -2.9, 0.01)


func test_failed_or_foreign_inventory_actions_make_no_success_sound() -> void:
	var inventory := _hand.inventory()
	inventory.request_equip(-1)
	inventory.request_drop(99)
	inventory.request_stow(-2)
	assert_eq(_events.size(), 0)
	assert_true(inventory.collect("banana"))
	assert_eq(_events.size(), 1)
	assert_eq(_events[0].cue, &"pickup")
	assert_false(_events[0].positional)
	inventory.request_stow(-1)
	assert_eq(_events[1].cue, &"equip")
	_hand.peer_id = 2
	inventory.request_equip(0)
	assert_eq(_events.size(), 2)


func test_world_voices_are_bounded_and_survive_emitter_removal() -> void:
	var emitter := Node3D.new()
	add_child(emitter)
	GameAudio.play_at(emitter, &"explosion", Vector3.ONE)
	emitter.queue_free()
	await get_tree().process_frame
	assert_eq(_audio._world.get_child_count(), 1)
	for index: int in 40:
		GameAudio.play_at(self, &"smg", Vector3(index, 0, 0))
	assert_eq(_audio._world.get_child_count(), GameAudio.MAX_WORLD_VOICES)
	for index: int in 10:
		GameAudio.play_ui(self, &"equip")
	assert_eq(_audio._ui.get_child_count(), GameAudio.MAX_UI_VOICES)
	_audio._clear(Network.mode)
	assert_eq(_audio._world.get_child_count(), 0)
	assert_eq(_audio._ui.get_child_count(), 0)


func test_finished_voices_cleanup_and_assets_are_short_non_looping_clips() -> void:
	for cue: StringName in [
		&"pistol",
		&"smg",
		&"shotgun",
		&"awp",
		&"explosion",
		&"impact",
		&"hit",
		&"open",
		&"close",
		&"equip",
		&"pickup",
		&"drop",
		&"door_open",
		&"door_close",
		&"door_locked",
		&"door_unlock",
		&"key_pickup"
	]:
		var profile := _audio._profile(cue)
		var stream := profile[0] as AudioStream
		assert_not_null(stream)
		if stream is AudioStreamWAV:
			assert_eq((stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED)
		else:
			assert_false((stream as AudioStreamOggVorbis).loop)
		assert_gt(stream.get_length(), 0.01)
		assert_lt(stream.get_length(), 3.0)
	GameAudio.play_at(self, &"smg", Vector3.ZERO)
	GameAudio.play_ui(self, &"equip")
	await RealTime.wait(get_tree(), 1.0)
	assert_eq(_audio._world.get_child_count(), 0)
	assert_eq(_audio._ui.get_child_count(), 0)


func test_unknown_sound_and_invalid_position_do_not_allocate_voices() -> void:
	GameAudio.play_at(self, &"not-a-cue", Vector3.ZERO)
	GameAudio.play_at(self, &"pistol", Vector3.INF)
	assert_eq(_events.size(), 0)
	assert_eq(_audio._world.get_child_count(), 0)


func test_door_feedback_replaces_status_text_and_only_follows_accepted_actions() -> void:
	var door := preload("res://features/room_doors/swing_door.tscn").instantiate() as SwingDoor
	door.key_id = "upper_study_key"
	add_child_autofree(door)
	_player.net_position = Vector3(0, 1, -1.5)
	assert_eq(door.interaction_text(), "Use door")
	assert_eq(door.find_children("*", "Label3D", true, false).size(), 0)
	door.use()
	assert_eq(_events.size(), 1)
	assert_eq(_events[0].cue, &"door_locked")
	assert_true(_events[0].positional)
	door.use()
	assert_eq(_events.size(), 1, "Repeated denied requests cannot spam sound")
	assert_true(_hand.inventory().collect("upper_study_key"))
	assert_eq(_events[1].cue, &"key_pickup")
	assert_false(_hand.inventory().collect("upper_study_key"))
	assert_eq(_events.size(), 2, "Rejected duplicate pickup is silent")
	door.use()
	assert_eq(_events[2].cue, &"door_unlock")
	assert_eq(_events[3].cue, &"door_open")
	door.use()
	assert_eq(_events.size(), 4)
	await RealTime.wait(get_tree(), 0.5)
	door.use()
	assert_eq(_events[4].cue, &"door_close")
	_player.net_position = Vector3(0, 1, -20)
	await RealTime.wait(get_tree(), 0.5)
	door.use()
	assert_eq(_events.size(), 5, "Out-of-range request is silent")


func test_stock_weapons_use_six_distinct_compact_shot_samples() -> void:
	var samples: Dictionary = {}
	for cue: StringName in [&"pistol", &"smg", &"m4a4", &"ak47", &"shotgun", &"awp"]:
		var stream := _audio._profile(cue)[0] as AudioStreamWAV
		assert_not_null(stream)
		assert_eq(stream.mix_rate, 11025)
		assert_false(stream.stereo)
		assert_lte(stream.get_length(), .81)
		assert_eq(stream.format, AudioStreamWAV.FORMAT_IMA_ADPCM)
		samples[stream.resource_path] = true
	assert_eq(samples.size(), 6)


func test_reload_cues_play_once_at_stages_and_stop_after_holstering() -> void:
	_hand.set_process(false)
	_hand.net_item_id = "pistol"
	_hand.inventory().collect("ammo:pistol:20")
	_hand.pistol.advance(0)
	_hand.request_primary_action()
	_events.clear()
	assert_eq(_hand.pistol.entity._evaluate(2, &"reload", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_events.size(), 0)
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.ACCEPTED)
	_hand.pistol.advance(.1)
	assert_eq(_events.size(), 0)
	_hand.pistol.advance(.3)
	assert_eq(_events.size(), 1)
	assert_eq(_events[0].cue, &"reload_mag_out")
	_hand.pistol.advance(1.3)
	assert_eq(_events.size(), 3)
	assert_eq(_events[1].cue, &"reload_mag_in")
	assert_eq(_events[2].cue, &"reload_charge")
	_hand.pistol.advance(3)
	assert_eq(_events.size(), 3)
	_hand._fire_cooldown = 0
	_hand.request_primary_action()
	_events.clear()
	_hand.pistol._reload(1, {})
	_hand.net_item_id = "banana"
	_hand.pistol.advance(3)
	assert_eq(_events.size(), 0)
