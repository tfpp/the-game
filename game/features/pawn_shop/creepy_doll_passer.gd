class_name CreepyDollPasser
extends Node3D
## A scenery actor: the server owns clock boundaries and the shared walking phase.

const INTERVAL := 600.0
const START := Vector3(-28, 0, 31.1)
const FINISH := Vector3(8, 0, 31.1)
const DURATION := 36.0 / 1.1
const FADE_DURATION := 3.0

@export var net_phase := -1.0:
	set(value):
		net_phase = value
		_received_msec = Time.get_ticks_msec()

var _received_msec := 0
var _next_boundary := 0.0
var _started_at := -1.0
var _animation: AnimationPlayer

@onready var entity: NetworkedEntity = $NetworkedEntity
@onready var visual: Node3D = $Visual
@onready var ambience: AudioStreamPlayer3D = $Ambience


func _ready() -> void:
	_animation = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation:
		_animation.play("Walk")
		_animation.pause()
	_reset(Network.mode)
	entity.session_reset.connect(_reset)
	_present(0.0)


func _process(_delta: float) -> void:
	if entity.is_authority():
		server_update(Time.get_unix_time_from_system())
	_present(float(Time.get_ticks_msec() - _received_msec) / 1000.0)


func server_update(now: float) -> void:
	if not entity.is_authority() or not is_finite(now):
		return
	if now >= _next_boundary:
		_started_at = floor(now / INTERVAL) * INTERVAL
		_next_boundary = next_boundary(now)
	var elapsed := now - _started_at
	net_phase = (
		elapsed
		if _started_at >= 0.0 and elapsed >= 0.0 and elapsed < DURATION + FADE_DURATION
		else -1.0
	)


static func next_boundary(now: float) -> float:
	return (floor(now / INTERVAL) + 1.0) * INTERVAL


func _reset(_mode: Network.Mode) -> void:
	ambience.stop()
	if entity.is_authority():
		_started_at = -1.0
		_next_boundary = next_boundary(Time.get_unix_time_from_system())
		net_phase = -1.0


func _present(extrapolation: float) -> void:
	var elapsed := net_phase + extrapolation
	visual.visible = net_phase >= 0.0 and elapsed < DURATION
	visual.position = START.lerp(FINISH, clampf(elapsed / DURATION, 0.0, 1.0))
	if visual.visible and _animation:
		var walk := _animation.get_animation("Walk")
		_animation.seek(fposmod(elapsed, walk.length), true)
	_present_audio(elapsed)


func _present_audio(elapsed: float) -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	if net_phase < 0.0 or elapsed >= DURATION + FADE_DURATION:
		ambience.stop()
		return
	var gain := clampf((DURATION + FADE_DURATION - elapsed) / FADE_DURATION, .0001, 1.0)
	ambience.volume_db = -14.0 + linear_to_db(gain)
	if not ambience.playing:
		ambience.play(maxf(elapsed, 0.0))
	elif absf(ambience.get_playback_position() - elapsed) > .5:
		ambience.seek(maxf(elapsed, 0.0))


func _exit_tree() -> void:
	if is_instance_valid(ambience):
		ambience.stop()
