class_name PlayerHeight
extends RefCounted
## Identity math and feet-anchored presentation. Account IDs never leave the server.

const BASE_METERS := 1.8288
const SOR_METERS := 0.2032


static func for_identity(identity: int, account_name: String) -> float:
	# Treat the requested double quote literally as eight inches.
	if account_name.strip_edges().to_lower() == "sor":
		return SOR_METERS
	# Eleven repeatable heights from 1.64592 to 2.10312 m. Peer 1 keeps the
	# original build in offline previews. Avoid RNG and platform-dependent hashes.
	return BASE_METERS + float((absi(identity) % 11 * 37) % 11 - 4) * 0.04572


static func eye_scale(player: Player) -> float:
	return float(player.get_meta(&"height_eye_scale", 1.0))


static func apply_eyes(player: Player, factor: float) -> void:
	var previous := eye_scale(player)
	if not player.has_meta(&"height_eye_scale"):
		player.movement = player.movement.duplicate() as MovementConfig
	if not is_equal_approx(previous, factor):
		player.movement.eye_height *= factor / previous
	player.set_meta(&"height_eye_scale", factor)
	var camera := player.get_node_or_null("Camera") as Camera3D
	if player.is_local() and is_instance_valid(camera) and not camera.is_queued_for_deletion():
		if not camera.has_meta(&"height_base_near"):
			camera.set_meta(&"height_base_near", camera.near)
		camera.near = float(camera.get_meta(&"height_base_near")) * minf(factor, 1.0)
		player._update_camera()


static func apply_avatar(model: BlockPlayerModel, factor: float, hull: float) -> void:
	# The costume already scales its inner rig. Scale the outer avatar to the
	# final requested height, so Sor stays eight inches in every costume.
	var costume := BlockPlayerModel.PENGUIN_HEIGHT_SCALE if model.body_type == &"penguin" else 1.0
	var bounds := model.human.surface.get_aabb()
	var bottom := bounds.position.y
	var authored_height := bounds.size.y
	if model.body_type == &"penguin":
		# Foot bottom: -0.17 -0.30 -0.05. Head top: -0.17 +0.65 +0.19 +0.17.
		bottom = -0.52
		authored_height = 1.36
	var visual_scale := factor * BASE_METERS / authored_height
	model.scale = Vector3.ONE * visual_scale / costume
	model.position.y = -hull * 0.5 - bottom * visual_scale
	model.set_meta(&"standing_height_scale", factor)
