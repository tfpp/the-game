class_name GunRig
extends Node3D
## One player's currently equipped generated gun: what it is, how much ammo is
## loaded, and where its visual sits, for everyone watching. Spawned by the gun
## machine feature (gun_machine.gd) as a companion of the matching Player, since
## core/player isn't ours to edit — see `_mount_transform` for how it tracks the
## player without being parented to it, the same approach features/holdables/hand.gd
## uses for held items.
##
## Holding and ammo are server-authoritative like the rest of shared state
## (game/AGENTS.md): clients only ever request an action, and the server decides.

const LOCAL_OFFSET := Transform3D(Basis(), Vector3(0.28, -0.22, -0.55))
const REMOTE_SHOULDER_OFFSET := Vector3(0.32, 1.15, 0.2)
const FLASH_DURATION_S := 0.05

## Replicated (server -> everyone). See the synchronizer config in gun_rig.tscn.
@export var net_stats: Dictionary = {}
@export var net_ammo_in_mag := 0
@export var net_ammo_reserve := 0

## Set from spawn data (see gun_machine.gd), identically on every peer, before this
## node enters the tree, so it doesn't need its own synchronizer property.
var peer_id := 0

var _mounted_signature := ""
var _view: Node3D
var _flash_timer := 0.0
var _fire_cooldown := 0.0

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	add_to_group(&"gun_rigs")
	var fire_mouse := InputEventMouseButton.new()
	fire_mouse.button_index = MOUSE_BUTTON_LEFT
	var fire_pad := InputEventJoypadButton.new()
	fire_pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	Controls.ensure_action(&"gun_fire", [fire_mouse, fire_pad])
	var reload_key := InputEventKey.new()
	reload_key.physical_keycode = KEY_R
	var reload_pad := InputEventJoypadButton.new()
	reload_pad.button_index = JOY_BUTTON_X
	Controls.ensure_action(&"gun_reload", [reload_key, reload_pad])
	_rebuild_view()


func _process(delta: float) -> void:
	if _signature(net_stats) != _mounted_signature:
		_rebuild_view()
	var player := _player()
	visible = player != null and not net_stats.is_empty()
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
	if net_stats.is_empty():
		return
	if event.is_action_pressed(&"gun_fire"):
		request_fire.rpc_id(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gun_reload"):
		request_reload.rpc_id(1)
		get_viewport().set_input_as_handled()


## Server-only: equips `stats` (see GunGenerator.generate), fully loaded. Replaces
## whatever was held before — the machine calls this after a successful purchase.
func equip(stats: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	net_stats = stats.duplicate(true)
	net_ammo_in_mag = int(stats["magazine_size"])
	net_ammo_reserve = int(stats["total_ammo"]) - net_ammo_in_mag


## Server-only: the trash can empties the rig with no refund.
func discard() -> void:
	if not multiplayer.is_server():
		return
	net_stats = {}
	net_ammo_in_mag = 0
	net_ammo_reserve = 0


func has_ammo_to_fire() -> bool:
	return not net_stats.is_empty() and net_ammo_in_mag >= int(net_stats["barrel_count"])


@rpc("any_peer", "call_local", "reliable")
func request_fire() -> void:
	if not multiplayer.is_server() or not _is_own_request() or _fire_cooldown > 0.0:
		return
	if not has_ammo_to_fire():
		return
	var barrel_count := int(net_stats["barrel_count"])
	_fire_cooldown = 1.0 / maxf(float(net_stats["fire_rate"]), 0.01)
	net_ammo_in_mag -= barrel_count
	_play_fire.rpc()
	var player := _player()
	var gun_machine := get_tree().get_first_node_in_group(&"gun_machine_root")
	if player == null or gun_machine == null:
		return
	var ammo_type: GunGenerator.AmmoType = net_stats["ammo_type"]
	var profile := GunGenerator.profile(ammo_type)
	var origin := _mount_transform(player).origin
	var jitter := deg_to_rad(float(net_stats["spread_degrees"]))
	for _barrel: int in barrel_count:
		for _pellet: int in int(profile["pellets"]):
			var yaw := player.net_yaw + randf_range(-jitter, jitter)
			var pitch := clampf(
				player.net_pitch + randf_range(-jitter, jitter), deg_to_rad(-89.0), deg_to_rad(89.0)
			)
			var direction := _aim_direction(yaw, pitch)
			(
				gun_machine
				. call(
					"spawn_projectile",
					{
						"ammo_type": ammo_type,
						"position": origin,
						"velocity": direction * float(net_stats["projectile_speed"]),
						"damage": float(net_stats["damage"]),
						"shooter_peer": peer_id,
					}
				)
			)


@rpc("authority", "call_local", "reliable")
func _play_fire() -> void:
	_flash_timer = FLASH_DURATION_S
	_set_flash(true)


@rpc("any_peer", "call_local", "reliable")
func request_reload() -> void:
	if not multiplayer.is_server() or not _is_own_request() or net_stats.is_empty():
		return
	var needed := int(net_stats["magazine_size"]) - net_ammo_in_mag
	var moved := mini(needed, net_ammo_reserve)
	net_ammo_in_mag += moved
	net_ammo_reserve -= moved


## A GunRig tracks its owner by peer id (see `peer_id`), not scene position, so any
## script holding a `Player` can find its rig this way.
static func for_peer(tree: SceneTree, target_peer_id: int) -> GunRig:
	for node: Node in tree.get_nodes_in_group(&"gun_rigs"):
		var rig := node as GunRig
		if rig != null and rig.peer_id == target_peer_id:
			return rig
	return null


func _is_own_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	var effective := sender if sender != 0 else multiplayer.get_unique_id()
	return effective == peer_id


func _player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer_id):
			return player
	return null


## Where this rig's gun sits: near the camera for the local player — a first-person
## viewmodel offset to the bottom right, aiming down the camera's forward axis at the
## reticle — or at the shoulder, angled to match the player's full aim direction
## (yaw *and* pitch, unlike features/holdables/hand.gd's fixed-orientation puppets),
## for everyone else watching one.
func _mount_transform(player: Player) -> Transform3D:
	if player.is_local():
		var camera := player.get_node("Camera") as Node3D
		return camera.global_transform * LOCAL_OFFSET
	var body := player.get_node("Body") as Node3D
	var aim := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0.0))
	var shoulder := (
		body.global_transform.origin + body.global_transform.basis * REMOTE_SHOULDER_OFFSET
	)
	return Transform3D(aim, shoulder)


func _aim_direction(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)


func _rebuild_view() -> void:
	_mounted_signature = _signature(net_stats)
	for child: Node in _mount.get_children():
		_mount.remove_child(child)
		child.queue_free()
	_view = null
	if net_stats.is_empty():
		return
	_view = GunView.build(net_stats)
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


func _signature(stats: Dictionary) -> String:
	return JSON.stringify(stats)
