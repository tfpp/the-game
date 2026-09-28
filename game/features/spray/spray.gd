class_name Spray
extends Node
## Lets any player spray a decal onto the surface they're looking at by pressing T.
##
## The client raycasts from its camera and asks the server; the server checks the spot is
## near the sender's player, then tells every peer to place the decal. Only the newest
## MAX_SPRAYS stay in the world.

const SPRAY_ACTION := &"spray"
const REACH := 6.0
## Extra distance the server allows beyond REACH for latency and camera offset.
const REACH_SLACK := 4.0
const MAX_SPRAYS := 60
const COOLDOWN_MSEC := 1000
const SIZE := 1.2
const SPRAY_SIZE_PX := 128

var _sprays: Array[Decal] = []
var _last_sprayed := {}
var _texture: Texture2D


func _ready() -> void:
	Controls.ensure_action(SPRAY_ACTION, [_key_event(KEY_T)])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(SPRAY_ACTION) or not Controls.gameplay_active():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var local := get_tree().get_first_node_in_group(&"local_player") as CollisionObject3D
	if local:
		query.exclude = [local.get_rid()]
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	get_viewport().set_input_as_handled()
	request_spray.rpc_id(1, hit["position"], hit["normal"])


@rpc("any_peer", "call_local", "reliable")
func request_spray(point: Vector3, normal: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not is_valid_request(player.global_position, point, normal):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_sprayed.get(peer_id, -COOLDOWN_MSEC)) < COOLDOWN_MSEC:
		return
	_last_sprayed[peer_id] = now
	place_spray.rpc(point, normal.normalized())


@rpc("authority", "call_local", "reliable")
func place_spray(point: Vector3, normal: Vector3) -> void:
	var decal := Decal.new()
	decal.texture_albedo = _spray_texture()
	decal.size = Vector3(SIZE, 0.4, SIZE)
	decal.cull_mask = 1
	add_child(decal)
	decal.global_transform = Transform3D(surface_basis(normal), point + normal * 0.05)
	_sprays.append(decal)
	while _sprays.size() > MAX_SPRAYS:
		_sprays.pop_front().queue_free()


## True if `point` is a plausible spray spot for a player standing at `player_pos`.
static func is_valid_request(player_pos: Vector3, point: Vector3, normal: Vector3) -> bool:
	if not (point.is_finite() and normal.is_finite()):
		return false
	if not is_equal_approx(normal.length(), 1.0):
		return false
	return player_pos.distance_to(point) <= REACH + REACH_SLACK


## A basis whose Y axis is the surface normal, so the decal (which projects along its
## -Y) paints onto the surface, with its texture upright on walls.
static func surface_basis(normal: Vector3) -> Basis:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var x := up.cross(normal).normalized()
	var z := x.cross(normal).normalized()
	return Basis(x, normal, z)


## The default spray. A stand-in drawn in code (a bold "!" mark) until the requested
## image is added:.
func _spray_texture() -> Texture2D:
	if _texture == null:
		_texture = _default_texture()
	return _texture


static func _default_texture() -> Texture2D:
	var img := Image.create(SPRAY_SIZE_PX, SPRAY_SIZE_PX, false, Image.FORMAT_RGBA8)
	var center := Vector2(SPRAY_SIZE_PX, SPRAY_SIZE_PX) / 2.0
	for y in SPRAY_SIZE_PX:
		for x in SPRAY_SIZE_PX:
			var d := Vector2(x, y).distance_to(center) / (SPRAY_SIZE_PX / 2.0)
			var bar := absf(x - center.x) < 9.0 and y > 20 and y < 82
			var dot := Vector2(x, y).distance_to(Vector2(center.x, 100.0)) < 10.0
			if d < 1.0 and (bar or dot):
				img.set_pixel(x, y, Color(0.95, 0.15, 0.15, 1.0))
			elif d < 1.0 and d > 0.88:
				img.set_pixel(x, y, Color(0.95, 0.15, 0.15, 0.9))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
