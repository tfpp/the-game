extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Light := preload("res://features/world_builder/skylight_light.gd")


func test_skylight_cuts_roof_preserves_floor_and_seals_glass_above_ceiling() -> void:
	var layout := Layout.compile(
		{
			"version": 1,
			"cell_size": 1.5,
			"style": {"kit": "modern"},
			"rooms":
			[
				{
					"id": "Room",
					"size": [8, 8],
					"at": [-8, -8],
					"elevation": 2,
					"height": 4,
					"skylight": true
				}
			]
		}
	)
	assert_eq(layout["errors"], [])
	var root := Builder.build(layout)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var definition: Dictionary = layout["skylights"][0]
	var center: Vector3 = definition["position"] + Vector3(0.3, 0, 0.3)
	var space := root.get_world_3d().direct_space_state
	var below := center + Vector3.DOWN * 0.3
	var opening := PhysicsRayQueryParameters3D.create(below, center + Vector3.UP * 0.1)
	assert_true(space.intersect_ray(opening).is_empty(), "Original roof no longer covers aperture")
	var glass := space.intersect_ray(PhysicsRayQueryParameters3D.create(below, center + Vector3.UP))
	assert_false(glass.is_empty(), "Glass seals skylight")
	if not glass.is_empty():
		assert_almost_eq((glass.position as Vector3).y, center.y + 0.1875, 0.01)
	var floor := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(below, center + Vector3.DOWN * 5)
	)
	assert_false(floor.is_empty())
	if not floor.is_empty():
		assert_almost_eq((floor.position as Vector3).y, 2.0, 0.02)
	var edge: Vector3 = definition["position"] + Vector3(definition["size"].x / 2 + 0.5, 0, 0)
	assert_false(
		(
			space
			. intersect_ray(
				PhysicsRayQueryParameters3D.create(edge + Vector3.DOWN, edge + Vector3.UP)
			)
			. is_empty()
		),
		"Surrounding roof is preserved"
	)
	assert_not_null(root.get_node("Skylights/Room/SkyPane"))
	assert_eq(
		root.find_children("PendantLight*", "OmniLight3D", true, false).size(),
		0,
		"No fixture hanging across the skylight"
	)


func test_live_fill_is_bright_in_day_and_remains_readable_at_night() -> void:
	var light := OmniLight3D.new()
	light.set_script(Light)
	light.set_day_factor(1)
	assert_eq(light.light_energy, 3.0)
	light.set_day_factor(0)
	assert_almost_eq(light.light_energy, 1.2, 0.001)
	light.free()


func test_invalid_skylight_and_roofless_skylight_are_rejected() -> void:
	var spec := {"version": 1, "rooms": [{"id": "Room", "size": [8, 8], "skylight": "yes"}]}
	assert_false(Layout.compile(spec)["errors"].is_empty())
	spec["rooms"][0]["skylight"] = true
	spec["ceiling"] = false
	assert_false(Layout.compile(spec)["errors"].is_empty())


func test_saved_hotels_have_thirteen_skylights_with_room_sized_light_coverage() -> void:
	var total := 0
	for id: String in ["hotel", "modern", "deco"]:
		var scene := load("res://features/hotel_annex/%s.scn" % id) as PackedScene
		var root := scene.instantiate()
		var skylights := root.get_node("Skylights")
		total += skylights.get_child_count()
		for lantern: Node3D in skylights.get_children():
			var light := lantern.get_node("Daylight") as OmniLight3D
			assert_gte(light.omni_range, 8.0)
			assert_true(light.shadow_enabled, "Room walls contain the skylight fill")
			var sky := lantern.get_node("SkyPane") as MeshInstance3D
			assert_false(
				(sky.get_active_material(0) as ShaderMaterial).shader.code.contains("ALPHA")
			)
		root.free()
	assert_eq(total, 13)
