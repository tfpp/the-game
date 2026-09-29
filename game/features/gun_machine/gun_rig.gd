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

## Generated guns don't map onto features/holdables' fixed pistol/smg/shotgun/awp
## items, but their fire sounds are close enough stand-ins for each ammo type's
## rate of fire and punch, and reusing them avoids shipping duplicate audio assets.
const AMMO_SOUND_CUES := {
	GunGenerator.AmmoType.BUCKSHOT: &"shotgun",
	GunGenerator.AmmoType.RIFLE: &"smg",
	GunGenerator.AmmoType.LOW_CALIBER: &"pistol",
	GunGenerator.AmmoType.ROCKET: &"awp",
	GunGenerator.AmmoType.GRENADE: &"awp",
	GunGenerator.AmmoType.PLASMA: &"smg",
	GunGenerator.AmmoType.RAY: &"pistol",
}

## Replicated (server -> everyone). See the synchronizer config in gun_rig.tscn.
@export var net_stats: Dictionary = {}
@export var net_ammo_in_mag := 0
@export var net_ammo_reserve := 0
## False while a rolled gun sits in reserve instead of in the player's hand — e.g.
## after `holster()` makes room for a holdable weapon (features/holdables). The rolled
## stats stay put either way, so re-selecting this slot (see `request_equip_rig`)
## doesn't cost another trip to the machine.
@export var net_equipped := true

## Set from spawn data (see gun_machine.gd), identically on every peer, before this
## node enters the tree, so it doesn't need its own synchronizer property.
var peer_id := 0

var _mounted_signature := ""
var _view: Node3D
var _flash_timer := 0.0
var _fire_cooldown := 0.0
## Throttles how often an automatic gun's held-trigger poll (`_maybe_auto_fire`)
## sends a fresh `request_fire` request, separately from `_fire_cooldown` (which is
## only ever set on the server — see that var's uses in `request_fire`).
var _auto_fire_cooldown := 0.0

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	add_to_group(&"gun_rigs")
	# Player updates at priority 0; third-person camera updates at 10. Mount after
	# both so this frame's camera transform is current, not one frame stale (the
	# stale read plus the engine's own physics-interpolation smoothing on top of an
	# already-interpolated camera transform is what made the viewmodel jitter).
	process_priority = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	visible = player != null and is_active()
	if player != null:
		global_transform = _mount_transform(player)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta
	if _auto_fire_cooldown > 0.0:
		_auto_fire_cooldown -= delta
	_maybe_auto_fire()


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id() or not Controls.gameplay_active():
		return
	if not is_active():
		return
	if event.is_action_pressed(&"gun_fire"):
		get_viewport().set_input_as_handled()
		# Automatic guns fire from the held-trigger poll below instead, so every tick
		# it's held gets a shot rather than just the initial press.
		if not bool(net_stats.get("is_automatic", false)):
			request_fire.rpc_id(1)
	elif event.is_action_pressed(&"gun_reload"):
		request_reload.rpc_id(1)
		get_viewport().set_input_as_handled()


## Automatic guns keep firing, at their own fire rate, for as long as `gun_fire`
## stays held — "still held" isn't an event Godot's input system emits, so this
## polls every frame instead of reacting in `_unhandled_input` the way a
## semi-automatic gun's single-shot-per-press does.
func _maybe_auto_fire() -> void:
	if peer_id != multiplayer.get_unique_id() or not Controls.gameplay_active():
		return
	if net_stats.is_empty():
		return
	var held := Input.is_action_pressed(&"gun_fire")
	if not should_auto_fire(bool(net_stats.get("is_automatic", false)), held, _auto_fire_cooldown):
		return
	_auto_fire_cooldown = 1.0 / maxf(float(net_stats["fire_rate"]), 0.01)
	request_fire.rpc_id(1)


## Pure decision of whether the held-trigger poll should send another fire request
## this frame, kept static and side-effect-free so it's unit-testable without a real
## `Input` or `Controls` singleton.
static func should_auto_fire(is_automatic: bool, held: bool, cooldown_remaining: float) -> bool:
	return is_automatic and held and cooldown_remaining <= 0.0


## Server-only: equips `stats` (see GunGenerator.generate), fully loaded. Replaces
## whatever was held before — the machine calls this after a successful purchase.
## Also holsters any holdable weapon (features/holdables) the player has in hand, so
## the two systems never both keep a weapon equipped at once.
func equip(stats: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_holster_holdable_weapon()
	net_stats = stats.duplicate(true)
	net_ammo_in_mag = int(stats["magazine_size"])
	net_ammo_reserve = int(stats["total_ammo"]) - net_ammo_in_mag
	net_equipped = true


## Server-only: hides this rig's gun without discarding its rolled stats, so a
## holdable weapon (features/holdables) can take over the hand. Called by
## PlayerInventory when a weapon is equipped or picked up.
func holster() -> void:
	if not multiplayer.is_server():
		return
	net_equipped = false


## Server-only: the trash can empties the rig with no refund.
func discard() -> void:
	if not multiplayer.is_server():
		return
	net_stats = {}
	net_ammo_in_mag = 0
	net_ammo_reserve = 0
	net_equipped = true


## True while this rig's gun is the one actually in the player's hand — as opposed to
## holstered in reserve (see `holster`) or never rolled at all.
func is_active() -> bool:
	return net_equipped and not net_stats.is_empty()


func has_ammo_to_fire() -> bool:
	return not net_stats.is_empty() and net_ammo_in_mag >= int(net_stats["barrel_count"])


## Re-selects this rig's holstered gun, holstering any holdable weapon in hand first —
## the reverse of a holdable weapon holstering this rig. Used by
## features/weapon_hotbar to let scrolling or a hotbar key bring the rig gun back out.
@rpc("any_peer", "call_local", "reliable")
func request_equip_rig() -> void:
	if not multiplayer.is_server() or not _is_own_request() or net_stats.is_empty():
		return
	_holster_holdable_weapon()
	net_equipped = true


@rpc("any_peer", "call_local", "reliable")
func request_fire() -> void:
	if not multiplayer.is_server() or not _is_own_request() or _fire_cooldown > 0.0:
		return
	if not is_active() or not has_ammo_to_fire():
		return
	var player := _player()
	var gun_machine := get_tree().get_first_node_in_group(&"gun_machine_root")
	if player == null or gun_machine == null:
		return
	var barrel_count := int(net_stats["barrel_count"])
	_fire_cooldown = 1.0 / maxf(float(net_stats["fire_rate"]), 0.01)
	net_ammo_in_mag -= barrel_count
	var ammo_type: GunGenerator.AmmoType = net_stats["ammo_type"]
	var profile := GunGenerator.profile(ammo_type)
	var origin := _aim_origin(player)
	_play_fire.rpc(ammo_type, origin)
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


## `origin` is the authoritative eye position `request_fire` fired from (see
## `_aim_origin`), broadcast so the sound comes from the shot itself rather than
## wherever this listening peer's own copy of the shooter happens to be.
@rpc("authority", "call_local", "reliable")
func _play_fire(ammo_type: GunGenerator.AmmoType, origin: Vector3) -> void:
	_flash_timer = FLASH_DURATION_S
	_set_flash(true)
	GameAudio.play_at(self, AMMO_SOUND_CUES.get(ammo_type, &"pistol"), origin)


@rpc("any_peer", "call_local", "reliable")
func request_reload() -> void:
	if not multiplayer.is_server() or not _is_own_request() or not is_active():
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


## Server-only: stows whatever holdable weapon (features/holdables) this peer has in
## hand, if any, so this rig can take over the hand without two weapons showing at
## once. A no-op if there's no matching Hand or it isn't holding a weapon.
func _holster_holdable_weapon() -> void:
	var hand := Hand.for_peer(get_tree(), peer_id)
	if hand != null:
		hand.inventory().holster_weapon()


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


## Where this rig's barrel tip is for whoever's watching it right now — the FPS
## viewmodel muzzle for the local shooter, the third-person model's muzzle for
## everyone else. Purely cosmetic (see `Projectile._visual_offset`): a shot fired
## straight down the local camera's own forward axis barely moves in screen space
## and is easy to miss, so the projectile's visual starts here and eases onto the
## real, `_aim_origin`-based trajectory instead of popping in already on-axis.
func muzzle_position() -> Vector3:
	if _view == null:
		return global_position
	var muzzle := _view.get_node_or_null("Muzzle") as Node3D
	return muzzle.global_position if muzzle != null else global_position


func _aim_direction(yaw: float, pitch: float) -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)


## The authoritative shot origin: the player's eye position, independent of camera
## mode or the cosmetic viewmodel mount (see `_mount_transform`). `request_fire` runs
## on the server, where the shooter is never `is_local()`, so using the mount
## transform here spawned every projectile from the third-person shoulder pose even
## for a shooter in first-person view — this is what made spawns look off in FPS.
func _aim_origin(player: Player) -> Vector3:
	return (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)


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
		var glow := GunFx.flash(Color(1.0, 0.85, 0.5, 0.9), 0.12)
		glow.name = "MuzzleFlash"
		muzzle.add_child(glow)
	elif not active and existing != null:
		existing.queue_free()


func _signature(stats: Dictionary) -> String:
	return JSON.stringify(stats)
