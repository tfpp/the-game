extends Node3D
## Run this scene in an exported release, where assert expressions are removed.

const LAYOUT := preload("res://features/street_district/layout.gd")
var _failed := false


func _ready() -> void:
	_check(not OS.is_debug_build(), "Probe requires a release template, not the editor")
	position = Vector3(0, 0, -2200)
	var district := LAYOUT.build(self)
	var joins: Array = district.get_meta("joins")
	_check(joins.size() == 36, "Expected all 36 socket joins")
	for join: Dictionary in joins:
		var a := join["from"] as ProceduralSocketAttachment
		var b := join["to"] as ProceduralSocketAttachment
		_check(not a.join_id.is_empty(), "Join never executed")
		_check(a.errors_with(b).is_empty(), "Socket positions do not align")
		_check(a.cap == null and b.cap == null, "Connected sockets still capped")
	for row: int in range(3):
		for column: int in range(3):
			var junction := district.get_node("J%d%d" % [row, column]) as Node3D
			var expected := Vector3(column * 28 - 28, 0, row * 28 - 6)
			_check(junction.position.distance_to(expected) < .001, "Junction collapsed")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for point: Vector3 in [Vector3(0, 0, 3), Vector3(-28, 0, 28), Vector3(28, 0, 56)]:
		var world := to_global(point)
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(world + Vector3.UP, world + Vector3.DOWN)
		)
		_check(not hit.is_empty(), "Street floor missing at %s" % point)
	if not _failed:
		print("STREET_RELEASE_PASS: 36 joins, nine distinct junctions, supported arrival and roads")
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("STREET_RELEASE_FAIL: " + message)
