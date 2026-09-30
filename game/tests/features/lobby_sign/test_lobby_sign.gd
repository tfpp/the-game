extends GutTest

## The south-lobby proclamation plaque: mounted flush on the real south wall, facing
## north into the lobby, readable and clear, with text that actually fits and renders.
## Probes the actual room collision the way tests/features/annex/test_easter_eggs.gd and
## tests/features/elevator/test_elevator_placement.gd do.

const FeatureScene := preload("res://features/lobby_sign/feature.tscn")
const RoomScene := preload("res://world/room.tscn")

const MANDARIN := "中国共产党万岁"
const CAPTION := "ALL HAIL THE CHINESE COMMUNIST PARTY"
const ROOT_POSITION := Vector3(10.5, 4.0, 34.0)
const SOUTH_WALL_FACE_Z := 34.0
const CASINO_ELEVATOR_CAB := Vector3(-9.7, 1.1, 32.3)
const SCONCE_X := 20.0
const PLAQUE_HALF_WIDTH := 2.35

var _feature: Node3D
var _room: Node3D


func before_each() -> void:
	_feature = FeatureScene.instantiate() as Node3D
	add_child_autofree(_feature)
	_room = RoomScene.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(3)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _feature.get_world_3d().direct_space_state.intersect_ray(query)


func _mandarin() -> Label3D:
	return _feature.get_node("Mandarin") as Label3D


func _caption() -> Label3D:
	return _feature.get_node("Caption") as Label3D


func _face() -> MeshInstance3D:
	return _feature.get_node("Face") as MeshInstance3D


## The readable side of a Label3D is its local +Z.
func _front() -> Vector3:
	return _feature.global_basis.z


func test_plaque_mounts_flush_on_the_solid_south_wall() -> void:
	assert_eq(_feature.global_position, ROOT_POSITION, "Pinned to the south lobby wall")
	var front := _front()
	assert_almost_eq(front.z, -1.0, 0.001, "Sign faces north, into the lobby and gaming floor")
	assert_almost_eq(front.x, 0.0, 0.001)
	# Solid wallpaper behind every part of the plaque, flush at the wall face.
	for local: Vector3 in [
		Vector3(0, 0, 0.1),
		Vector3(-2.35, 0.95, 0.1),
		Vector3(2.35, 0.95, 0.1),
		Vector3(-2.35, -0.95, 0.1),
		Vector3(2.35, -0.95, 0.1),
		Vector3(-2.35, 0, 0.1),
		Vector3(2.35, 0, 0.1),
		Vector3(0, 0.95, 0.1),
		Vector3(0, -0.95, 0.1),
	]:
		var point := _feature.to_global(local)
		var wall := _ray(point + front * 0.3, point - front * 0.3)
		assert_false(wall.is_empty(), "Wall must be solid behind %s" % local)
		if not wall.is_empty():
			var hit := wall["position"] as Vector3
			assert_almost_eq(hit.z, SOUTH_WALL_FACE_Z, 0.01, "Mounted on the wall face")
			assert_gt(
				(wall["normal"] as Vector3).dot(front), 0.99, "Wall face and sign agree on facing"
			)


func test_plaque_sits_east_of_the_south_exit_and_clear_of_the_elevator() -> void:
	# The main south exit is the x -2.5...2.5 gap between the two south wall boxes.
	assert_gt(
		ROOT_POSITION.x - PLAQUE_HALF_WIDTH, 2.5, "Plaque stays clear of the south exit doorway"
	)
	assert_lt(ROOT_POSITION.x + PLAQUE_HALF_WIDTH, SCONCE_X - 0.5, "Clear of the lobby sconce")
	assert_gt(_feature.global_position.distance_to(CASINO_ELEVATOR_CAB), 15.0, "Clear of the cab")


func test_readable_from_a_standing_spot_and_from_the_gaming_floor() -> void:
	var front := _front()
	var label_point := _mandarin().global_position + front * 0.06
	var approach := _mandarin().global_position + front * 1.5
	var sight := _ray(approach, label_point)
	assert_true(sight.is_empty(), "Nothing blocks the reading distance")
	var floor_hit := _ray(approach + Vector3(0, 1, 0), approach - Vector3(0, 8, 0))
	assert_false(floor_hit.is_empty(), "Reading spot has floor support")
	if not floor_hit.is_empty():
		assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.01, "Lobby floor level")
	var shape := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	shape.shape = capsule
	shape.transform.origin = Vector3(approach.x, 0.94, approach.z)
	assert_true(
		_feature.get_world_3d().direct_space_state.intersect_shape(shape).is_empty(),
		"Standing clearance in front of the sign"
	)
	# The sightline from the gaming floor across the promenade stays open.
	for eye: Vector3 in [Vector3(7.0, 1.7, 10.0), Vector3(2.0, 1.7, 5.0)]:
		var seen := _ray(eye, label_point)
		assert_true(seen.is_empty(), "Visible from the gaming floor at %s" % eye)


func test_every_glyph_renders_and_the_text_fits_the_plaque() -> void:
	var face_size := (_face().mesh as BoxMesh).size
	var face_width := face_size.x - 0.25
	var face_height := face_size.y
	for label: Label3D in [_mandarin(), _caption()]:
		assert_not_null(label.font, "Needs an explicit font")
		for ch in label.text:
			var glyph: String = ch
			assert_true(
				label.font.has_char(glyph.unicode_at(0)), "Font renders %s (no tofu boxes)" % glyph
			)
		var measured: Vector2 = label.font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size
		)
		var outline: int = 2 * label.outline_size * label.pixel_size
		assert_gt(label.pixel_size, 0.0)
		assert_lte(
			measured.x * label.pixel_size + outline,
			face_width,
			"%s text fits the plaque width" % label.name
		)
		var half_line := measured.y * label.pixel_size * 0.5
		assert_lte(
			absf(label.position.y) + half_line,
			face_height * 0.5 + 0.01,
			"%s text fits the plaque height" % label.name
		)
	assert_eq(_mandarin().text, MANDARIN)
	assert_eq(_caption().text, CAPTION)
	assert_eq(
		_mandarin().font.resource_path,
		"res://assets/fonts/notosanssc/NotoSansSC-Bold-subset.ttf",
		"Mandarin line uses the CJK subset font"
	)


func test_static_budget_and_identical_on_every_peer() -> void:
	var second := FeatureScene.instantiate() as Node3D
	add_child_autofree(second)
	assert_eq(_feature.find_children("*", "MeshInstance3D", true, false).size(), 5)
	assert_eq(_feature.find_children("*", "Label3D", true, false).size(), 2)
	assert_eq(second.find_children("*", "MeshInstance3D", true, false).size(), 5)
	for node: Node in _feature.find_children("*", "", true, false):
		assert_null(node.get_script(), "Pure static scenery, no scripts")
		assert_false(node is CollisionObject3D, "No colliders: the wall carries the plaque")
		assert_false(node is Light3D, "No extra lights")
		if node is GeometryInstance3D:
			var geo := node as GeometryInstance3D
			assert_eq(geo.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_eq(geo.visibility_range_end, 0.0, "Visible from anywhere in the room")
	for name: String in ["Mandarin", "Caption"]:
		var label := _feature.get_node(name) as Label3D
		var copy := second.get_node(name) as Label3D
		assert_eq(label.text, copy.text)
		assert_eq(label.transform, copy.transform)
		assert_eq(label.font.resource_path, copy.font.resource_path)
		assert_false(label.double_sided)
		assert_false(label.no_depth_test)
		assert_false(label.shaded)
	assert_eq(
		_feature.global_transform,
		second.global_transform,
		"Same immutable scene on every peer, late joiners included"
	)
