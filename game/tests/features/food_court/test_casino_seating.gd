extends GutTest
## The casino uses the original booth authority and pose owner, not another registry.

const CASINO := preload("res://features/casino_hub/casino_gridmap.tscn")
const COURT := preload("res://features/food_court/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")

var _casino: Node3D
var _court: FoodCourt
var _player: Player


func before_each() -> void:
	_casino = CASINO.instantiate() as Node3D
	add_child_autofree(_casino)
	_court = COURT.instantiate() as FoodCourt
	add_child_autofree(_court)
	_player = PLAYER.instantiate() as Player
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	await wait_physics_frames(3)


func test_all_casino_anchors_share_the_booth_registry_and_snapshot() -> void:
	assert_eq(_court.seats.size(), 57, "32 booth seats plus 25 casino seats")
	assert_eq(_court.net_seats.size(), _court.seats.size())
	assert_eq(_court.entity.replicated_properties, [NodePath(".:net_seats")])
	for index: int in range(32, _court.seats.size()):
		assert_same(_court.seats[index].get("court"), _court)
		assert_eq(_court.seats[index].get("index"), index)
	assert_eq(get_tree().get_nodes_in_group(&"seating").size(), 1)


func test_balcony_cushions_face_bar_and_exit_on_deck() -> void:
	for index: int in range(32, _court.seats.size()):
		var seat := _court.seats[index]
		if not str(seat.get_path()).contains("MariachiBalcony"):
			continue
		assert_almost_eq(seat.global_position.y, 5.74, 0.001)
		assert_gt((-seat.global_basis.z).dot(Vector3.LEFT), 0.99)
		var exit := _court.stand_position(index)
		assert_almost_eq(exit.y, 5.0, 0.001)
		assert_almost_eq(exit.x, -27.15, 0.001)
		_near(index)
		_court.request_sit(index)
		_court._update_local_pin(0.016)
		assert_almost_eq(_player.global_position.y, 5.91, 0.001)
		assert_false(_player.is_physics_processing())
		_court.request_stand()
		_court._update_local_pin(0.016)
		assert_true(_player.is_physics_processing())
		_player.set_physics_process(false)


func test_every_exit_has_floor_and_clear_standing_capsule() -> void:
	var hull := CapsuleShape3D.new()
	hull.radius = _player.movement.hull_radius_m()
	hull.height = _player.movement.hull_height_m()
	for index: int in range(32, _court.seats.size()):
		var exit := _court.stand_position(index)
		var ray := PhysicsRayQueryParameters3D.create(
			exit + Vector3.UP * 0.2, exit + Vector3.DOWN * 0.2, 1
		)
		var space := _casino.get_world_3d().direct_space_state
		assert_false(space.intersect_ray(ray).is_empty(), "Exit floor: %s" % exit)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.collision_mask = 1
		query.exclude = [_player.get_rid()]
		query.transform.origin = exit + Vector3.UP * (hull.height / 2.0 + 0.02)
		assert_true(space.intersect_shape(query).is_empty(), "Exit clearance: %s" % exit)


func test_server_rejects_unknown_far_and_competing_occupants() -> void:
	var index := 32
	_near(index)
	assert_eq(_court.entity._evaluate(5, &"sit", {"seat": index}), NetworkedEntity.Result.DENIED)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": index}), NetworkedEntity.Result.ACCEPTED)
	var other := PLAYER.instantiate() as Player
	other.set_multiplayer_authority(2)
	add_child_autofree(other)
	other.net_position = _player.net_position
	assert_eq(_court.entity._evaluate(2, &"sit", {"seat": index}), NetworkedEntity.Result.DENIED)
	_court._on_peer_disconnected(1)
	_player.net_position = Vector3.ZERO
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": index}), NetworkedEntity.Result.DENIED)


func test_card_guest_yields_and_returns_and_late_snapshot_sets_pose() -> void:
	var models := MODELS.instantiate()
	add_child_autofree(models)
	models._process(0.0)
	var seat := _casino.get_node("Furnishings/PlayerSeat0_1") as Node3D
	var index: int = seat.get("index")
	var guest := _casino.get_node("Furnishings/Patron0_1") as Node3D
	_near(index)
	_court.request_sit(index)
	seat.call("_process", 0.0)
	assert_false(guest.visible)
	var model := _player.get_node("Body/Avatar") as BlockPlayerModel
	model._process(1.0)
	assert_true(model.seated, "Initial occupancy uses the existing avatar pose query")
	_court._on_player_died(1, 2)
	seat.call("_process", 0.0)
	assert_true(guest.visible)
	model._process(1.0)
	assert_false(model.seated)


func test_teleport_and_reset_release_casino_occupancy() -> void:
	_near(32)
	_court.request_sit(32)
	_court._update_local_pin(0.016)
	_player.global_position = Vector3(0, 1, 16)
	_player.net_position = _player.global_position
	_court._update_local_pin(0.016)
	assert_false(_court.is_seated(1))
	assert_true(_player.is_physics_processing())
	_near(32)
	_court.request_sit(32)
	_court._reset_session(Network.Mode.OFFLINE)
	assert_false(_court.is_seated(1))


func _near(index: int) -> void:
	_player.global_position = _court.seats[index].global_position + Vector3.UP * 0.3
	_player.net_position = _player.global_position
