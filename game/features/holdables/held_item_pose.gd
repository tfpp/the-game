class_name HeldItemPose
extends RefCounted
## Visual grip placement is separate from the authoritative aim origin. Cameras
## can move behind the player without moving the item or the origin of a shot.

const FIRST_PERSON_OFFSET := Vector3(0.22, -0.23, -0.43)
const SHOULDER_PIVOT := Vector3(0.22, 0.30, 0.0)
const REACH := Vector3(0.0, -0.12, -0.34)


static func aim_basis(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


static func world_grip(
	origin: Vector3, yaw: float, pitch: float, height_scale: float = 1.0
) -> Transform3D:
	var facing := Basis(Vector3.UP, yaw)
	var aim := aim_basis(yaw, pitch)
	var feet := origin - Vector3.UP * PlayerHeight.BASE_METERS * 0.5
	var pivot := Vector3.UP * PlayerHeight.BASE_METERS * 0.5 + facing * SHOULDER_PIVOT
	return Transform3D(
		aim.scaled(Vector3.ONE * height_scale), feet + (pivot + aim * REACH) * height_scale
	)


static func align_grip(view: Node3D) -> void:
	var grip := view.get_node_or_null("Grip") as Marker3D
	if grip != null:
		view.transform = grip.transform.affine_inverse()
