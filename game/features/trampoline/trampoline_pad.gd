extends StaticBody3D
## A springy square that launches anyone standing on it into the air.
##
## Launch math lives in trampoline_bounce.gd (unit-tested) the same way other
## features keep pure math separate from the scene (see features/water/water.gd).
##
## Player movement is client-authoritative (see game/AGENTS.md): only the owning
## peer may change a player's velocity, so `_on_body_entered` only launches a
## `Player` when `is_local()` is true, and that check runs identically for every
## player on their own peer. The squash-and-stretch animation is purely cosmetic
## and plays on every peer for any body, like the penguin's explosion, since it
## doesn't need to match exactly.

const TrampolineBounce := preload("res://features/trampoline/trampoline_bounce.gd")

const SQUASH_SCALE := Vector3(1.2, 0.5, 1.2)
const SQUASH_DURATION_S := 0.15

var _rest_scale := Vector3.ONE
var _squash_tween: Tween

@onready var _surface: MeshInstance3D = $Surface
@onready var _launch_area: Area3D = $LaunchArea


func _ready() -> void:
	_rest_scale = _surface.scale
	_launch_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	_play_squash()
	if body is Player and body.is_local():
		body.velocity.y = TrampolineBounce.launch_velocity_y(body.velocity.y)


func _play_squash() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_surface.scale = _rest_scale * SQUASH_SCALE
	_squash_tween = create_tween()
	(
		_squash_tween
		. tween_property(_surface, "scale", _rest_scale, SQUASH_DURATION_S)
		. set_trans(Tween.TRANS_ELASTIC)
		. set_ease(Tween.EASE_OUT)
	)
