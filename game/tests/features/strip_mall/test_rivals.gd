extends GutTest

const MALL := preload("res://features/strip_mall/feature.tscn")
const AUDIO := preload("res://features/game_audio/feature.tscn")
const Rivalry := preload("res://features/strip_mall/rivalry.gd")
const RivalModel := preload("res://features/strip_mall/rival_model.gd")

var _mall: Node3D
var _room: StreamedRoom
var _rivalry: Node3D


func before_each() -> void:
	_mall = MALL.instantiate() as Node3D
	add_child_autofree(_mall)
	_room = _mall.get_node("Room") as StreamedRoom
	_room.set_physics_process(false)
	_rivalry = _room.get_node("Rivalry") as Node3D
	_rivalry.set_physics_process(false)


func test_server_alternates_speakers_then_rests_without_backlog() -> void:
	assert_eq(_rivalry.active_speaker(), -1)
	_rivalry.advance(10.0)
	for turn: int in 6:
		assert_eq(_rivalry.net_turn, turn)
		assert_eq(_rivalry.active_speaker(), turn % 2)
		assert_true(_rivalry.bubble_visible(turn % 2))
		assert_false(_rivalry.bubble_visible(1 - turn % 2))
		_rivalry.advance(3.3)
		assert_false(_rivalry.bubble_visible(turn % 2))
		_rivalry.advance(.71)
	assert_eq(_rivalry.net_turn, -1)
	assert_eq(_rivalry.net_remaining, 10.0)
	_rivalry.advance(100.0)
	assert_eq(_rivalry.net_turn, 0, "Stalls emit only one current yell")


func test_non_authority_and_invalid_time_cannot_advance_argument() -> void:
	_rivalry.set_multiplayer_authority(2)
	_rivalry.advance(20.0)
	assert_eq(_rivalry.net_turn, -1)
	assert_eq(_rivalry.net_remaining, 10.0)
	_rivalry.set_multiplayer_authority(1)
	for delta: float in [-1.0, 0.0, NAN, INF]:
		_rivalry.advance(delta)
	assert_eq(_rivalry.net_remaining, 10.0)
	assert_eq(_rivalry.entity._evaluate(2, &"yell", {}), NetworkedEntity.Result.UNKNOWN_ACTION)


func test_streaming_preserves_scheduler_and_late_presentation_does_not_replay_audio() -> void:
	var audio := AUDIO.instantiate() as GameAudio
	add_child_autofree(audio)
	watch_signals(audio)
	_rivalry.advance(10.0)
	assert_signal_not_emitted(audio, "sound_started", "Unloaded plaza stays quiet")
	_room.load_room()
	assert_signal_not_emitted(audio, "sound_started", "Loading during a turn is silent")
	var content := _room.get_node("Content/RivalRestaurants")
	var kim := content.get_node("CityWok/Owner") as RivalModel
	assert_eq(kim._rivalry, _rivalry)
	assert_true(_rivalry.bubble_visible(0), "Late-loaded body reads current turn")
	_rivalry.advance(4.0)
	assert_signal_emitted(audio, "sound_started")
	_room.unload_room()
	await wait_physics_frames(1)
	assert_true(is_instance_valid(_rivalry.entity))
	assert_eq(_rivalry.net_turn, 1)
	_room.load_room()
	assert_eq(_room.get_node("Content/RivalRestaurants/CitySushi/Owner").character, 1)
	_rivalry._reset(Network.Mode.OFFLINE)
	assert_eq(_rivalry.net_turn, -1)


func test_current_bubbles_and_gestures_follow_snapshot_without_extra_audio() -> void:
	_room.load_room()
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = _room.to_global(Vector3(15, 1.65, 40))
	camera.make_current()
	var content := _room.get_node("Content/RivalRestaurants")
	var kim := content.get_node("CityWok/Owner") as RivalModel
	var junichi := content.get_node("CitySushi/Owner") as RivalModel
	_rivalry.net_turn = 0
	_rivalry.net_remaining = 3.0
	kim._process(.1)
	junichi._process(.1)
	assert_true(kim._bubble.visible)
	assert_false(junichi._bubble.visible)
	assert_eq(kim._bubble.text, Rivalry.LINES[0].replace("! ", "!\n"))
	assert_gt(kim.avatar._right_arm.rotation.x, 1.0)
	_rivalry.net_turn = 1
	kim._process(.1)
	junichi._process(.1)
	assert_false(kim._bubble.visible)
	assert_true(junichi._bubble.visible)
	_rivalry.net_remaining = .5
	junichi._process(.1)
	assert_false(junichi._bubble.visible)
	camera.global_position += Vector3(100, 0, 0)
	_rivalry.net_remaining = 3.0
	junichi._process(.1)
	assert_false(junichi._bubble.visible, "Distant rigs do not pose or show bubbles")


func test_yell_uses_existing_audio_pool_at_the_correct_owner() -> void:
	_room.load_room()
	var audio := AUDIO.instantiate() as GameAudio
	add_child_autofree(audio)
	watch_signals(audio)
	_rivalry.advance(10.0)
	assert_signal_emitted_with_parameters(
		audio, "sound_started", [&"city_wok_yell", true, _room.to_global(Vector3(9, 1.5, 41))]
	)
	_rivalry.advance(4.0)
	assert_signal_emitted_with_parameters(
		audio, "sound_started", [&"city_sushi_yell", true, _room.to_global(Vector3(21, 1.5, 41))]
	)
	for cue: StringName in [&"city_wok_yell", &"city_sushi_yell"]:
		var stream := audio._profile(cue)[0] as AudioStreamWAV
		assert_almost_eq(stream.get_length(), 1.0, .001)
		assert_eq(stream.mix_rate, 22050)
		assert_false(stream.stereo)


func test_replication_declares_initial_turn_and_countdown_for_late_joiners() -> void:
	var sync := _rivalry.entity.get_node("Sync") as MultiplayerSynchronizer
	var config := sync.replication_config
	for field: NodePath in [NodePath(".:net_turn"), NodePath(".:net_remaining")]:
		assert_true(config.has_property(field))
		assert_true(config.property_get_spawn(field))
	assert_eq(sync.get_multiplayer_authority(), 1)


func test_counters_and_owners_face_each_other_and_rest_on_paving() -> void:
	_room.load_room()
	await wait_physics_frames(4)
	var content := _room.get_node("Content/RivalRestaurants")
	var wok := content.get_node("CityWok") as Node3D
	var sushi := content.get_node("CitySushi") as Node3D
	assert_eq(wok.position, Vector3(9, 0, 43))
	assert_eq(sushi.position, Vector3(21, 0, 43))
	var direction := (sushi.global_position - wok.global_position).normalized()
	assert_almost_eq(wok.global_basis.z.dot(direction), 1.0, .001)
	assert_almost_eq(sushi.global_basis.z.dot(-direction), 1.0, .001)
	for stand: Node3D in [wok, sushi]:
		var owner := stand.get_node("Owner") as RivalModel
		assert_gt((-owner.global_basis.z.normalized()).dot(stand.global_basis.z), .99)
		assert_almost_eq(owner.global_position.y, 0.0, .001)
		assert_almost_eq(owner.global_position.distance_to(stand.global_position), 2.0, .001)
		assert_almost_eq(_room.to_local(owner.global_position).z, 41.0, .001)
		var body := stand.get_node("Body/Collision") as CollisionShape3D
		assert_almost_eq(body.global_position.y - (body.shape as BoxShape3D).size.y / 2, 0.0, .001)
		var customer := stand.to_global(Vector3(0, 1, 2))
		var ray := PhysicsRayQueryParameters3D.create(customer, customer - Vector3(0, 3, 0))
		var hit := _room.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, .01)


func test_south_plaza_route_and_existing_zabka_approach_stay_clear() -> void:
	_room.load_room()
	await wait_physics_frames(4)
	var shape := CapsuleShape3D.new()
	shape.radius = .4064
	shape.height = 1.8288
	for route: Array in [
		[Vector3(26, .95, 38), Vector3(26, .95, 43)],
		[Vector3(26, .95, 40), Vector3(15, .95, 40)],
		[Vector3(15, .95, 40), Vector3(15, .95, 43)],
		[Vector3(11, .95, 43), Vector3(19, .95, 43)]
	]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform.origin = _room.to_global(route[0])
		query.motion = route[1] - route[0]
		assert_almost_eq(_room.get_world_3d().direct_space_state.cast_motion(query)[0], 1.0, .001)
	for path: String in ["CityWokDestination", "CitySushiDestination"]:
		assert_true(_room.contains((_room.get_node(path) as Node3D).global_position))


func test_costumes_reuse_avatar_and_distinguish_the_named_characters() -> void:
	_room.load_room()
	var content := _room.get_node("Content/RivalRestaurants")
	var kim := content.get_node("CityWok/Owner") as RivalModel
	var junichi := content.get_node("CitySushi/Owner") as RivalModel
	assert_eq(kim.avatar.hair_style, "bald")
	assert_eq(junichi.avatar.hair_style, "classic")
	assert_eq(kim.avatar.shirt_id, "shirt:0")
	assert_eq(junichi.avatar.shirt_id, "shirt:0")
	assert_true(kim.head_items.has_node("Tooth"))
	assert_true(kim.head_items.has_node("CombOver0"))
	assert_eq(kim.avatar.pants_id, "pants:3")
	assert_true(kim.torso_items.has_node("VestBack"))
	assert_true(junichi.torso_items.has_node("Sash"))
	assert_eq((kim.get_node("NameTag") as Label3D).text, "Tuong Lu Kim")
	assert_eq((junichi.get_node("NameTag") as Label3D).text, "Junichi Takayama")
	assert_eq((content.get_node("CitySushi/Sign") as SignBoard).text, "CITY SUSHI")
