extends GutTest
## Structural checks for the trampoline feature (features/trampoline/feature.tscn):
## a handful of pads placed on open floor inside the main room.

const FEATURE_PATH := "res://features/trampoline/feature.tscn"
const PAD_SCRIPT := preload("res://features/trampoline/trampoline_pad.gd")

const MAIN_ROOM_HALF_EXTENT := 34.5


func test_feature_loads_with_at_least_two_pads() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var pads := _pads(root)
	assert_gte(pads.size(), 2)


func test_every_pad_sits_inside_the_main_room() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	for pad: Node3D in _pads(root):
		var pos := pad.global_position
		var inside := absf(pos.x) < MAIN_ROOM_HALF_EXTENT and absf(pos.z) < MAIN_ROOM_HALF_EXTENT
		assert_true(inside, "%s should sit inside the main room, got %s" % [pad.name, pos])


func test_every_pad_has_a_launch_area() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	for pad: Node3D in _pads(root):
		assert_not_null(pad.find_child("LaunchArea", false, false))


func _instantiate() -> Node3D:
	var scene := load(FEATURE_PATH) as PackedScene
	return scene.instantiate()


func _pads(root: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child: Node in root.get_children():
		if child.get_script() == PAD_SCRIPT:
			found.append(child)
	return found
