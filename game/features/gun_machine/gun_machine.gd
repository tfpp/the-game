class_name GunMachine
extends Node3D
## Root of the gun machine feature: a machine that sells a randomly generated gun
## for `PRICE_CENTS`, and a trash can next to it that discards whatever you're
## carrying. See README.md for the full picture.
##
## Server-authoritative spawning like features/holdables/holdables.gd: the server
## spawns a GunRig per connected peer (so everyone, including late joiners, sees the
## same replicated node) and a Projectile whenever one fires.

## A fresh account starts with exactly this much (features/money), so a new player
## can always afford one gun right away without waiting on income.
const PRICE_CENTS := 2000

const GUN_RIG_SCENE := preload("res://features/gun_machine/gun_rig.tscn")
const PROJECTILE_SCENE := preload("res://features/gun_machine/projectile.tscn")

var _next_projectile_id := 0

@onready var _rigs: Node3D = $Rigs
@onready var _rig_spawner: MultiplayerSpawner = $RigSpawner
@onready var _projectiles: Node3D = $Projectiles
@onready var _projectile_spawner: MultiplayerSpawner = $ProjectileSpawner


func _ready() -> void:
	add_to_group(&"gun_machine_root")
	_rig_spawner.spawn_function = _spawn_rig
	_projectile_spawner.spawn_function = _spawn_projectile
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


## Callable from anywhere via `.call("price_cents")` (a `const` isn't reachable
## through `Object.get()`, so the kiosk's price display goes through this instead).
func price_cents() -> int:
	return PRICE_CENTS


## Server: sells `peer` a fresh gun, deducting PRICE_CENTS from their wallet. Called
## by the machine kiosk (gun_machine_kiosk.gd) once it has confirmed range. Returns
## an error string on failure, or "" on success.
func purchase(peer: int) -> String:
	if not multiplayer.is_server():
		return "Server only"
	var rig := GunRig.for_peer(get_tree(), peer)
	if rig == null:
		return "No gun rig"
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		return "Wallet unavailable"
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, PRICE_CENTS)
	if result.has("error"):
		return str(result["error"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rig.equip(GunGenerator.generate(rng))
	return ""


## Server: empties `peer`'s rig with no refund. Called by the trash can
## (gun_machine_trash_can.gd).
func discard(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var rig := GunRig.for_peer(get_tree(), peer)
	if rig != null:
		rig.discard()


## Server: called by a GunRig (gun_rig.gd's `request_fire`) when it fires a shot.
func spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_next_projectile_id += 1
	var payload := data.duplicate()
	payload["id"] = _next_projectile_id
	_projectile_spawner.spawn(payload)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_clear(_rigs)
	_clear(_projectiles)
	if Network.is_authoritative():
		_rig_spawner.spawn({"peer": multiplayer.get_unique_id()})


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_rig_spawner.spawn({"peer": peer_id})


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := _rigs.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


## Runs on every peer (spawn_function), so authority is set identically everywhere.
func _spawn_rig(data: Variant) -> Node:
	var info := data as Dictionary
	var peer_id: int = info["peer"]
	var rig := GUN_RIG_SCENE.instantiate() as GunRig
	rig.name = str(peer_id)
	rig.peer_id = peer_id
	return rig


func _spawn_projectile(data: Variant) -> Node:
	var info := data as Dictionary
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.name = "Projectile%d" % int(info["id"])
	projectile.ammo_type = info["ammo_type"]
	projectile.position = info["position"]
	projectile.net_position = info["position"]
	projectile.velocity = info["velocity"]
	projectile.damage = float(info["damage"])
	projectile.shooter_peer = int(info["shooter_peer"])
	return projectile


func _clear(container: Node3D) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
