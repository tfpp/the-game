extends GutTest
## `jump_height_scale` (set externally by features/game_config/game_config.gd) scales
## how high a frog's hops arc, the same way hop_rate_scale scales how often it hops
## (see test_frog_hop_rate.gd).

const FROG := preload("res://features/frogs/frog.tscn")

var _world: Node3D
var _frog: Frog


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 1, 20)
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0, -0.5, 0)
	_world.add_child(floor_body)
	_frog = FROG.instantiate() as Frog
	_frog.jump_height = 0.5
	_world.add_child(_frog)
	await wait_physics_frames(2)
	_frog.set_physics_process(false)


func test_default_jump_height_scale_is_unscaled() -> void:
	assert_eq(_frog.jump_height_scale, 1.0)


func test_start_hop_scales_the_arc_height() -> void:
	_frog.jump_height_scale = 2.0
	_frog._fleeing = false
	_frog._start_hop()
	assert_almost_eq(_frog._hop_height, 1.0, 0.001)
