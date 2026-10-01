class_name HeldItemPose
extends RefCounted
## Visual grip placement is separate from the authoritative aim origin. Cameras
## can move behind the player without moving the item or the origin of a shot.

const FIRST_PERSON_OFFSET := Vector3(0.22, -0.23, -0.43)
const SHOULDER_PIVOT := Vector3(0.22, 0.30, 0.0)
const REACH := Vector3(0.0, -0.12, -0.34)


static func aim_basis(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


static func world_grip(origin: Vector3, yaw: float, pitch: float) -> Transform3D:
	var facing := Basis(Vector3.UP, yaw)
	var aim := aim_basis(yaw, pitch)
	return Transform3D(aim, origin + facing * SHOULDER_PIVOT + aim * REACH)


static func align_grip(view: Node3D) -> void:
	var grip := view.get_node_or_null("Grip") as Marker3D
	if grip != null:
		view.transform = grip.transform.affine_inverse()


## Mount after the player and camera updates; third person stays at the body.
static func player_mount(player: Player, offset: Vector3 = FIRST_PERSON_OFFSET) -> Transform3D:
	var body := player.get_node("Body") as Node3D
	if player.is_local() and not body.visible:
		var camera := player.get_node("Camera") as Node3D
		offset.y *= avatar_height_scale(body)
		return camera.global_transform * Transform3D(Basis.IDENTITY, offset)
	var yaw := player.yaw if player.is_local() else body.global_rotation.y
	var pitch := player.pitch if player.is_local() else player.net_pitch
	var origin := (
		player.get_global_transform_interpolated().origin
		if player.is_local()
		else player.global_position
	)
	return world_grip(origin, yaw, pitch)


static func avatar_height_scale(body: Node3D) -> float:
	var avatar := body.get_node_or_null("Avatar")
	if avatar != null and avatar.has_method("height_scale"):
		return avatar.call("height_scale")
	return 1.0
