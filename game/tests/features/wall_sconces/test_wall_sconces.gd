extends GutTest
## features/wall_sconces: every annex sconce is built, faces into its room, and the
## lamps brighten at night.

const FEATURE := preload("res://features/wall_sconces/feature.tscn")

var _sconces: WallSconces


func before_each() -> void:
	_sconces = FEATURE.instantiate() as WallSconces
	add_child_autofree(_sconces)
	_sconces.set_process(false)


func test_builds_one_sconce_with_a_light_per_spot() -> void:
	assert_eq(_sconces.get_child_count(), WallSconces.SPOTS.size())
	assert_eq(
		_sconces.find_children("*", "OmniLight3D", true, false).size(), WallSconces.SPOTS.size()
	)


func test_lamp_is_brighter_at_night() -> void:
	assert_gt(WallSconces.lamp_energy(1.0), WallSconces.lamp_energy(0.0))


func test_night_factor_is_a_unit_fraction() -> void:
	var factor := _sconces.current_night_factor()
	assert_between(factor, 0.0, 1.0)


func test_light_sits_in_front_of_the_wall_along_its_normal() -> void:
	var spot := WallSconces.SPOTS[0]
	var light := _sconces.get_child(0).get_child(2) as OmniLight3D
	var normal := Vector2(spot.z, spot.w)
	var offset := Vector2(light.global_position.x - spot.x, light.global_position.z - spot.y)
	assert_almost_eq(offset.x, normal.x * 0.9, 0.001)
	assert_almost_eq(offset.y, normal.y * 0.9, 0.001)
