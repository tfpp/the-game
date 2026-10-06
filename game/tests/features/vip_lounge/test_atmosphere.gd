extends GutTest

const Atmosphere := preload("res://features/vip_lounge/lounge_atmosphere.gd")
const CLUB := preload("res://features/vip_lounge/feature.tscn")
const INSIDE := Vector3(29.4, 6.6, -9.7)
const OUTSIDE := Vector3(21.5, 1.8, -15)

var atmosphere: Node3D
var camera: Camera3D


func before_each() -> void:
	atmosphere = Atmosphere.new()
	add_child_autofree(atmosphere)
	atmosphere.set_process(false)
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.position = INSIDE


func _fog() -> Environment:
	var environment := Environment.new()
	environment.fog_enabled = true
	environment.ambient_light_energy = 0.37
	environment.ambient_light_color = Color("e8c568")
	return environment


func test_world_fog_is_removed_only_in_lounge_without_changing_lighting() -> void:
	var world := World3D.new()
	world.environment = _fog()
	var viewport := SubViewport.new()
	viewport.world_3d = world
	add_child_autofree(viewport)
	camera.reparent(viewport)
	atmosphere.update_camera(camera)
	assert_not_same(camera.environment, world.environment)
	assert_false(camera.environment.fog_enabled)
	assert_false(camera.environment.volumetric_fog_enabled)
	assert_eq(camera.environment.ambient_light_energy, world.environment.ambient_light_energy)
	assert_eq(camera.environment.ambient_light_color, world.environment.ambient_light_color)
	assert_true(world.environment.fog_enabled, "Shared world fog is untouched")
	assert_false(world.environment.volumetric_fog_enabled)
	camera.position = OUTSIDE
	atmosphere.update_camera(camera)
	assert_null(camera.environment, "Outside views inherit the world again")


func test_explicit_camera_override_is_preserved_and_restored_on_exit() -> void:
	var original := _fog()
	camera.environment = original
	atmosphere.update_camera(camera)
	var clear := camera.environment
	atmosphere.update_camera(camera)
	assert_same(camera.environment, clear, "Do not allocate an environment every frame")
	assert_true(original.fog_enabled)
	assert_false(clear.fog_enabled)
	camera.position = OUTSIDE
	atmosphere.update_camera(camera)
	assert_same(camera.environment, original)


func test_camera_switch_and_missing_camera_restore_previous_view() -> void:
	var original := _fog()
	camera.environment = original
	atmosphere.update_camera(camera)
	var third_person := Camera3D.new()
	add_child_autofree(third_person)
	third_person.position = Vector3(27, 7, 0)
	atmosphere.update_camera(third_person)
	assert_same(camera.environment, original)
	assert_false(third_person.environment.fog_enabled)
	atmosphere.update_camera(null)
	assert_null(third_person.environment)


func test_unload_restores_camera_but_does_not_overwrite_another_effect() -> void:
	var original := _fog()
	camera.environment = original
	atmosphere.update_camera(camera)
	atmosphere._exit_tree()
	assert_same(camera.environment, original)
	atmosphere.update_camera(camera)
	var other := Environment.new()
	camera.environment = other
	atmosphere._exit_tree()
	assert_same(camera.environment, other)


func test_feature_wires_atmosphere_and_keeps_downstairs_outside_bounds() -> void:
	var club := CLUB.instantiate()
	assert_not_null(club.get_node_or_null("Atmosphere"))
	assert_eq(club.get_node("Atmosphere").get_script(), Atmosphere)
	assert_true(VipLounge.BOUNDS.has_point(club.get_node("UpstairsArrival").position))
	assert_false(VipLounge.BOUNDS.has_point(club.get_node("DownstairsArrival").position))
	club.free()
