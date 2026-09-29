class_name Mitch
extends CasinoPatron
## Mitch McConnell, wheeled around the slot aisles by his intern. Every so often
## he throws up a peace sign; Trump pats him on the head when they meet
## (`trump.gd`). The server times gestures and tells every peer with a cosmetic RPC.

const PEACE_MIN_S := 7.0
const PEACE_MAX_S := 14.0
const PEACE_HOLD_S := 2.5
const PEACE_BLEND_SPEED := 4.0

var _peace_timer := 0.0
var _peace_hold := 0.0
var _peace := 0.0


func _ready() -> void:
	super._ready()
	_peace_timer = randf_range(PEACE_MIN_S, PEACE_MAX_S)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or not net_alive or net_ragdoll:
		return
	_peace_timer -= delta
	if _peace_timer <= 0.0:
		_peace_timer = randf_range(PEACE_MIN_S, PEACE_MAX_S)
		_throw_peace_sign.rpc()


func _process(delta: float) -> void:
	_peace_hold = maxf(_peace_hold - delta, 0.0)
	var goal := 1.0 if _peace_hold > 0.0 else 0.0
	_peace = move_toward(_peace, goal, PEACE_BLEND_SPEED * delta)
	(_body as MitchModel).peace = _peace
	super._process(delta)


func is_throwing_peace_sign() -> bool:
	return _peace_hold > 0.0


## Server-only: stop in place for `seconds` (e.g. while Trump pats his head).
func hold(seconds: float) -> void:
	_pause = maxf(_pause, seconds)


@rpc("authority", "call_local", "reliable")
func _throw_peace_sign() -> void:
	_peace_hold = PEACE_HOLD_S
