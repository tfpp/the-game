class_name Projectile
extends Node3D
## A single fired round in flight: a bullet, pellet, rocket, grenade or plasma bolt,
## depending on `ammo_type`. Spawned by the gun machine feature (gun_machine.gd,
## `spawn_projectile`) when a GunRig fires — see that feature's README for why
## generated guns fire these instead of hitscanning.
##
## Server-authoritative flight and hit detection, like
## features/holdables/thrown_item.gd: the server integrates position and publishes
## `net_position`; other peers only smooth toward it and play the impact flash.

const REMOTE_SMOOTHING := 24.0
const MAX_LIFETIME_S := 6.0
const COLLISION_MASK := 1
## How long the visual takes to ease from the shooter's muzzle onto the real
## trajectory. See `_visual_offset`.
const MUZZLE_VISUAL_EASE_S := 0.08

## Replicated (server -> everyone). See the synchronizer config in projectile.tscn.
@export var net_position := Vector3.ZERO

## Set from spawn data (see gun_machine.gd's `spawn_projectile`), identically on
## every peer, before this node enters the tree, so they don't need synchronizer
## properties of their own.
var ammo_type: GunGenerator.AmmoType = GunGenerator.AmmoType.RIFLE
var velocity := Vector3.ZERO
var damage := 0.0
var shooter_peer := 0

var _bounces_left := 0
var _elapsed := 0.0
var _finished := false

## A purely cosmetic, per-viewer local-space offset on `_visual` (never networked;
## `position`/`net_position` stay exactly on the real, authoritative trajectory).
## The true shot origin is the shooter's eye (`GunRig._aim_origin`) so aiming is
## accurate, but a shot fired straight down the shooter's own view axis barely
## moves in screen space and is nearly invisible at this small a size. Starting the
## visual at the shooter's muzzle (offscreen-center, `GunRig.muzzle_position`) and
## easing it onto the real path over `MUZZLE_VISUAL_EASE_S` gives it visible
## motion for both the shooter and any third-person viewer, without changing where
## the shot actually is.
var _visual_offset := Vector3.ZERO
var _visual_offset_elapsed := 0.0

@onready var _visual: MeshInstance3D = $Visual


func _ready() -> void:
	position = net_position
	net_position = position
	var rig := GunRig.for_peer(get_tree(), shooter_peer)
	if rig != null:
		_visual_offset = rig.muzzle_position() - position
	var profile := GunGenerator.profile(ammo_type)
	_bounces_left = int(profile["bounces"])
	var color: Color = profile["color"]
	var mesh := _visual.mesh as SphereMesh
	mesh.radius = 0.08 if float(profile["explosion_radius"]) > 0.0 else 0.035
	mesh.height = mesh.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	_visual.material_override = material
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	var profile := GunGenerator.profile(ammo_type)
	velocity = ProjectileMath.fall(velocity, float(profile["gravity_scale"]), delta)
	var from := position
	var to := from + velocity * delta
	var shooter := _shooter()
	var exclude: Array[RID] = []
	if shooter != null:
		exclude.append(shooter.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, COLLISION_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_on_hit(hit, profile)
		return
	var fuse_s := float(profile["fuse_s"])
	if fuse_s > 0.0 and _elapsed >= fuse_s:
		position = to
		net_position = to
		_explode(profile)
		return
	if _elapsed >= MAX_LIFETIME_S:
		_finish()
		return
	position = to
	net_position = to


func _on_hit(hit: Dictionary, profile: Dictionary) -> void:
	var player := hit["collider"] as Player
	if player != null:
		position = hit["position"]
		net_position = position
		_apply_direct_hit(player, profile)
		return
	if _bounces_left > 0:
		velocity = ProjectileMath.bounce(velocity, hit["normal"])
		_bounces_left -= 1
		position = hit["position"] + hit["normal"] * 0.02
		net_position = position
		if _bounces_left <= 0 or ProjectileMath.should_settle(velocity):
			_explode(profile)
		return
	position = hit["position"]
	net_position = position
	_explode(profile)


func _apply_direct_hit(player: Player, profile: Dictionary) -> void:
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat != null:
		combat.call("apply_damage", player.get_multiplayer_authority(), damage, shooter_peer)
	_splash(profile, player.get_multiplayer_authority())
	_finish()


func _explode(profile: Dictionary) -> void:
	_splash(profile, 0)
	_finish()


## Everyone within the ammo type's explosion radius except `already_hit_peer` (the
## direct-hit target, if any — splash tapers to 0 at the radius, so a direct hit
## already covers that case) takes falloff damage, for the rockets and grenades that
## have one; a radius of 0 (every other ammo type) makes this a no-op.
func _splash(profile: Dictionary, already_hit_peer: int) -> void:
	var radius := float(profile["explosion_radius"])
	if radius <= 0.0:
		return
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat == null:
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var peer := player.get_multiplayer_authority()
		if peer == already_hit_peer:
			continue
		var distance := player.net_position.distance_to(net_position)
		var splash_damage := ProjectileMath.splash_damage(distance, radius, damage)
		if splash_damage > 0.0:
			combat.call("apply_damage", peer, splash_damage, shooter_peer)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_play_impact.rpc(net_position)
	queue_free()


## An event, not saved state: late joiners don't need to replay an old impact.
@rpc("authority", "call_local", "reliable")
func _play_impact(at: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var flash := OmniLight3D.new()
	flash.light_energy = 4.0
	flash.omni_range = 3.0
	flash.light_color = Color(1.0, 0.7, 0.3)
	parent.add_child(flash)
	flash.global_position = at
	var timer := get_tree().create_timer(0.12)
	await timer.timeout
	flash.queue_free()


func _process(delta: float) -> void:
	if _visual_offset != Vector3.ZERO:
		_visual_offset_elapsed += delta
		var ease := clampf(_visual_offset_elapsed / MUZZLE_VISUAL_EASE_S, 0.0, 1.0)
		_visual.position = _visual_offset.lerp(Vector3.ZERO, ease)
		if ease >= 1.0:
			_visual_offset = Vector3.ZERO
	if multiplayer.is_server() or _finished:
		return
	var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	position = position.lerp(net_position, t)


func _shooter() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == shooter_peer:
			return player
	return null
