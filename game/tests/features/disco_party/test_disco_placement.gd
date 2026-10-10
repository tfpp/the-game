extends GutTest
## The booth stands on the pit floor clear of the ramps and slots; the ball hangs
## from the hall ceiling over the pit centre, out of everyone's way.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const FEATURE := preload("res://features/disco_party/feature.tscn")

var _room: Node3D
var _party: DiscoParty


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_party = FEATURE.instantiate() as DiscoParty
	add_child_autofree(_party)
	_party.set_process(false)
	await wait_physics_frames(3)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [(_party.get_node("Collision") as CollisionObject3D).get_rid()]
	return _room.get_world_3d().direct_space_state.intersect_ray(query)


func test_booth_rests_on_the_pit_floor() -> void:
	var half := DiscoParty.BOOTH_SIZE / 2.0
	for corner: Vector3 in [
		Vector3(-half.x, 0, -half.z),
		Vector3(half.x, 0, -half.z),
		Vector3(-half.x, 0, half.z),
		Vector3(half.x, 0, half.z),
	]:
		var at := _party.global_position + corner
		var hit := _ray(at + Vector3.UP * 0.5, at + Vector3.DOWN)
		assert_false(hit.is_empty())
		assert_almost_eq((hit["position"] as Vector3).y, _party.global_position.y, 0.01)


func test_booth_keeps_the_ramp_lane_and_slot_aisle_clear() -> void:
	var half := DiscoParty.BOOTH_SIZE / 2.0
	var west := _party.global_position.x - half.x
	var east := _party.global_position.x + half.x
	assert_gt(west, 3.0 + 0.5, "ramps span x -3..3")
	assert_lt(east, 6.6 - 1.5, "1.5 m in front of the slot bank at x 6.6")
	# Nothing in the room geometry overlaps the booth volume.
	var shape := BoxShape3D.new()
	shape.size = DiscoParty.BOOTH_SIZE - Vector3.ONE * 0.05
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), _party.global_position + Vector3.UP * half.y)
	query.exclude = [(_party.get_node("Collision") as CollisionObject3D).get_rid()]
	assert_eq(_room.get_world_3d().direct_space_state.intersect_shape(query).size(), 0)


func test_ball_hangs_from_the_ceiling_above_head_height() -> void:
	var ball := _party.get_node("Ball") as Node3D
	assert_eq(ball.global_position, DiscoParty.BALL_GLOBAL)
	var top := DiscoParty.BALL_GLOBAL + Vector3.UP * DiscoParty.BALL_RADIUS
	var hit := _ray(top, top + Vector3.UP * 4.0)
	assert_false(hit.is_empty(), "ceiling above the ball")
	assert_almost_eq((hit["position"] as Vector3).y, DiscoParty.CEILING_Y, 0.3)
	var cable := _party.get_node("Cable") as MeshInstance3D
	var cord := cable.mesh as CylinderMesh
	assert_almost_eq(cable.global_position.y + cord.height / 2.0, DiscoParty.CEILING_Y, 0.001)
	assert_almost_eq(cable.global_position.y - cord.height / 2.0, top.y, 0.001)
	assert_gt(DiscoParty.BALL_GLOBAL.y - DiscoParty.BALL_RADIUS, 0.0 + 3.0, "above promenade heads")
