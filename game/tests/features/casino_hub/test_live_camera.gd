extends GutTest
## The live casino must not supply a camera that takes over the view before spawn.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const PREVIEW := preload("res://features/casino_hub/gridmap/preview.tscn")


func test_live_room_has_no_camera() -> void:
	var room := ROOM.instantiate() as Node3D
	add_child_autofree(room)
	assert_eq(room.find_children("*", "Camera3D", true, false).size(), 0)


func test_live_room_does_not_become_the_viewport_camera() -> void:
	var room := ROOM.instantiate() as Node3D
	add_child_autofree(room)
	await wait_process_frames(1)
	var camera := get_viewport().get_camera_3d()
	assert_true(camera == null or not room.is_ancestor_of(camera))


func test_preview_keeps_its_orthographic_overview() -> void:
	var state := PREVIEW.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"Overview":
			assert_eq(state.get_node_type(index), &"Camera3D")
			return
	fail_test("Standalone casino preview must keep its overview camera")
