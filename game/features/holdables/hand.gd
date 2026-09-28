class_name Hand
extends Node3D
## One player's held item: what they're holding, and where its visual sits, for
## everyone watching. Spawned by the holdables feature (holdables.gd) as a companion
## of the matching Player, since core/player isn't ours to edit — see
## `_mount_transform` for how it tracks the player without being parented to it.
##
## Holding is server-authoritative like the rest of shared state (game/AGENTS.md), so
## unlike Player's client-authoritative movement this keeps the default multiplayer
## authority (1, the server). Clients only ever request an action; the server decides.

const LOCAL_OFFSET := Transform3D(Basis(), Vector3(0.28, -0.22, -0.55))
const REMOTE_OFFSET := Transform3D(Basis(), Vector3(0.32, 1.1, 0.25))
const THROW_DISTANCE := 5.0
const FIRE_COOLDOWN_S := 0.25
const FLASH_DURATION_S := 0.06

## Replicated (server -> everyone). See the synchronizer config in hand.tscn.
@export var net_item_id := ""

## Set from spawn data (see holdables.gd), identically on every peer, before this node
## enters the tree, so it doesn't need its own synchronizer property.
var peer_id := 0

var _mounted_item_id := ""
var _view: Node3D
var _flash_timer := 0.0
var _fire_cooldown := 0.0

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	add_to_group(&"hands")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	Controls.ensure_action(&"primary_action", [mouse, pad])
	_rebuild_view()


func _process(delta: float) -> void:
	if net_item_id != _mounted_item_id:
		_rebuild_view()
	var player := _player()
	visible = player != null and not net_item_id.is_empty()
	if player != null:
		global_transform = _mount_transform(player)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id() or not Controls.gameplay_active():
		return
	if net_item_id.is_empty() or not event.is_action_pressed(&"primary_action"):
		return
	request_primary_action.rpc_id(1)
	get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func request_primary_action() -> void:
	if not multiplayer.is_server() or not _is_own_request():
		return
	var def := ItemCatalog.find(net_item_id)
	if def == null:
		return
	match def.category:
		ItemDefinition.Category.WEAPON:
			_fire()
		ItemDefinition.Category.FOOD:
			_eat(def)
		ItemDefinition.Category.PROP:
			_throw(def)


## Server: hands this an item, if it's empty. Called by pickups and landed throws.
func try_equip(item_id: String) -> bool:
	if not multiplayer.is_server() or not net_item_id.is_empty():
		return false
	net_item_id = item_id
	return true


## A Hand tracks its owner by peer id (see `peer_id`), not scene position, so any
## script holding a `Player` can find its hand this way.
static func for_peer(tree: SceneTree, target_peer_id: int) -> Hand:
	for node: Node in tree.get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand != null and hand.peer_id == target_peer_id:
			return hand
	return null


func _is_own_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	var effective := sender if sender != 0 else multiplayer.get_unique_id()
	return effective == peer_id


func _fire() -> void:
	if _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN_S
	_play_fire.rpc()


@rpc("authority", "call_local", "reliable")
func _play_fire() -> void:
	_flash_timer = FLASH_DURATION_S
	_set_flash(true)


func _eat(def: ItemDefinition) -> void:
	net_item_id = ""
	_play_eaten.rpc(def.id)


## An event, not saved state: late joiners don't need to replay an old bite.
@rpc("authority", "call_local", "reliable")
func _play_eaten(_item_id: String) -> void:
	pass


func _throw(def: ItemDefinition) -> void:
	var player := _player()
	if player == null:
		net_item_id = ""
		return
	net_item_id = ""
	var from := _mount_transform(player).origin
	var direction := ThrowMath.aim_direction(player.net_yaw, player.net_pitch)
	var to := _landing_point(from, direction)
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if holdables:
		holdables.call("spawn_thrown_item", def.id, from, to)


func _landing_point(from: Vector3, direction: Vector3) -> Vector3:
	var flat := ThrowMath.toss_target(from, direction, THROW_DISTANCE)
	var query := PhysicsRayQueryParameters3D.create(
		flat + Vector3.UP * 10.0, flat + Vector3.DOWN * 10.0
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else flat


## Where this hand's item sits: near the camera for the local player (a first-person
## viewmodel), or near the body's hand for everyone else watching a puppet.
func _mount_transform(player: Player) -> Transform3D:
	if player.is_local():
		var camera := player.get_node("Camera") as Node3D
		return camera.global_transform * LOCAL_OFFSET
	var body := player.get_node("Body") as Node3D
	return body.global_transform * REMOTE_OFFSET


func _player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer_id):
			return player
	return null


func _rebuild_view() -> void:
	_mounted_item_id = net_item_id
	for child: Node in _mount.get_children():
		_mount.remove_child(child)
		child.queue_free()
	_view = null
	var def := ItemCatalog.find(net_item_id)
	if def != null and def.view_scene != null:
		_view = def.view_scene.instantiate() as Node3D
		_mount.add_child(_view)


func _set_flash(active: bool) -> void:
	if _view == null:
		return
	var muzzle := _view.get_node_or_null("Muzzle")
	if muzzle == null:
		return
	var existing := muzzle.get_node_or_null("MuzzleFlash")
	if active and existing == null:
		var light := OmniLight3D.new()
		light.name = "MuzzleFlash"
		light.light_energy = 3.0
		light.omni_range = 2.5
		light.light_color = Color(1.0, 0.85, 0.5)
		muzzle.add_child(light)
	elif not active and existing != null:
		existing.queue_free()
