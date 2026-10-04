extends GutTest

const STREET := preload("res://features/pawn_shop/street.tscn")


func test_leaving_and_unloading_restore_camera_and_stop_audio() -> void:
	var street := STREET.instantiate()
	add_child_autofree(street)
	street.set_process(false)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	var original := Environment.new()
	camera.environment = original
	camera.position = Vector3(-9, 1.6, 26)
	street.update_camera(camera)
	assert_ne(camera.environment, original)
	assert_eq(camera.environment.background_mode, Environment.BG_SKY)
	assert_true(street.traffic.playing)
	camera.position = Vector3.ZERO
	street.update_camera(camera)
	assert_same(camera.environment, original)
	assert_false(street.traffic.playing)
	camera.position = Vector3(-9, 1.6, 26)
	street.update_camera(camera)
	remove_child(street)
	assert_same(camera.environment, original)
	assert_false(street.traffic.playing)
