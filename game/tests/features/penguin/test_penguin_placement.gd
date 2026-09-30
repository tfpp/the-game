extends GutTest
## Placement of the penguin couple in the west petting parlor, checked against the
## real room collision. Both patrol circles must lie on the flat parlor floor and
## stay clear of the benches, rails and plants (there is a bench row along x -21).
## No penguins are instanced here, so the rays only see the room.

const RoomScene := preload("res://world/room.tscn")

const HUSBAND_HOME := Vector3(-26, 0.4, 8)
const WIFE_HOME := Vector3(-23.8, 0.4, 12.3)
const BODY_HEIGHT := 0.4

var _room: Node3D


func before_each() -> void:
	_room = RoomScene.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(3)


func test_husband_circle_on_flat_clear_floor() -> void:
	_assert_circle(HUSBAND_HOME)


func test_wife_circle_on_flat_clear_floor() -> void:
	_assert_circle(WIFE_HOME)


func test_circles_meet_without_the_bodies_overlapping() -> void:
	var gap := WIFE_HOME.distance_to(HUSBAND_HOME) - 2.0 * PenguinWaddle.PATROL_RADIUS
	assert_gt(gap, 0.57, "Closest approach: beak-to-beak, no clipping")
	assert_lt(gap, PenguinWaddle.COUPLE_RADIUS, "Close enough for the happy reaction")


func _assert_circle(home: Vector3) -> void:
	for step: int in range(16):
		var angle := TAU * step / 16.0
		var point := PenguinWaddle.position_on_circle(home, PenguinWaddle.PATROL_RADIUS, angle)
		var down := PhysicsRayQueryParameters3D.create(
			point + Vector3(0, 2, 0), point + Vector3(0, -2, 0)
		)
		var floor_hit := _room.get_world_3d().direct_space_state.intersect_ray(down)
		assert_false(floor_hit.is_empty(), "Floor under the circle at %s" % point)
		if not floor_hit.is_empty():
			assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.03, "Flat parlor floor")
		var across := PhysicsRayQueryParameters3D.create(
			Vector3(home.x, BODY_HEIGHT, home.z), Vector3(point.x, BODY_HEIGHT, point.z)
		)
		var blocked := _room.get_world_3d().direct_space_state.intersect_ray(across)
		assert_true(blocked.is_empty(), "Circle clear of obstacles at %s" % point)
