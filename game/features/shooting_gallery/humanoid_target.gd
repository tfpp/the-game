class_name HumanoidTarget
extends AnimatableBody3D
## A standing shooting-gallery dummy: killable by any weapon, gibs with gore, and
## pops back up a few seconds later. Modeled closely on
## features/penguin/penguin.gd, but at a fixed spot rather than patrolling — a
## gallery target should always be where you last saw it, not wander off.
##
## Killable by any weapon: a physics body (not just a visual Node3D) so
## features/holdables/hand.gd's hitscan and features/gun_machine/projectile.gd's
## ray query can both hit it, in the `killable` group so they route to `take_hit`
## instead of features/combat's `apply_damage`, which is keyed by player peer id
## and doesn't apply here.

const RESPAWN_DELAY_S := 3.0

## Replicated (server -> everyone). See the synchronizer config in
## humanoid_target.tscn. Position never changes once spawned, so this is the only
## networked state — like features/penguin/penguin.gd's `net_alive`.
@export var net_alive := true

## Set by shooting_gallery.gd's spawn data, identically on every peer, before this
## node enters the tree — the same way features/frogs/frog.gd's `body_color` arrives.
var jumpsuit_color := Color(0.55, 0.35, 0.15)

var _respawn_timer := 0.0

@onready var _body: HumanoidTargetModel = $Body
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	add_to_group(&"killable")
	add_to_group(&"shooting_gallery_targets")
	_body.build(jumpsuit_color)
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if net_alive:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		net_alive = true


func _process(_delta: float) -> void:
	_body.visible = net_alive
	_collider.disabled = not net_alive


## Server-only: any weapon kills a dummy outright, regardless of its damage value —
## the same "killable with any weapon" contract features/penguin/penguin.gd's
## `take_hit` documents.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


## Cosmetic only — every peer plays its own gore locally, like
## features/penguin/penguin.gd's `_explode`.
@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)
	GoreSplatter.spawn(self, _body)
