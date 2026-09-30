class_name ProceduralSocketAttachment
extends Node3D
## Origin is floor centre; local +Z faces out of the module.

const POSITION_TOLERANCE := 0.001
const ANGLE_TOLERANCE := 0.001745329

@export var profile: ProceduralSocketProfile
@export var join_id := ""
var cap: Node3D


func placement_for(other: ProceduralSocketAttachment) -> Transform3D:
	return (
		global_transform
		* Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		* other.transform.affine_inverse()
	)


static func attach(
	from: ProceduralSocketAttachment, to: ProceduralSocketAttachment, id: String
) -> Array[String]:
	if id.is_empty():
		return ["Join ID is required"]
	if not from.join_id.is_empty() or not to.join_id.is_empty():
		return ["Socket is already attached"]
	if not from.profile.matches(to.profile):
		return ["Opening profiles differ"]
	var module := to.get_parent() as Node3D
	var original := module.global_transform
	module.global_transform = from.placement_for(to)
	var errors := from.errors_with(to)
	if not errors.is_empty():
		module.global_transform = original
		return errors
	from.open(id)
	to.open(id)
	return []


func errors_with(other: ProceduralSocketAttachment) -> Array[String]:
	var errors: Array[String] = []
	if not profile.matches(other.profile):
		errors.append("Opening profiles differ")
	if global_position.distance_to(other.global_position) > POSITION_TOLERANCE:
		errors.append("Floor origins do not align")
	if global_basis.z.angle_to(-other.global_basis.z) > ANGLE_TOLERANCE:
		errors.append("Outward normals do not oppose")
	if global_basis.y.angle_to(other.global_basis.y) > ANGLE_TOLERANCE:
		errors.append("Up axes do not align")
	var opposite := other.profile.boundary()
	for point: Vector3 in profile.boundary():
		var distance := INF
		for candidate: Vector3 in opposite:
			distance = minf(distance, to_global(point).distance_to(other.to_global(candidate)))
		if distance > POSITION_TOLERANCE:
			errors.append("Opening boundary does not align")
			break
	return errors


func open(id: String) -> void:
	join_id = id
	if is_instance_valid(cap):
		cap.get_parent().remove_child(cap)
		cap.free()
		cap = null
