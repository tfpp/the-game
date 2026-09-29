class_name RouletteTableView
extends Node3D
## Table model and spin presentation. Presentation only; never chooses results.
## Each peer animates the spin locally from the replicated snapshot: the rotor spins up,
## the ball orbits the track the other way and drops inward, and once the server settles
## the result the ball rolls into that pocket and rides the rotor.

const MODEL := preload("res://assets/roulette/models/roulette_table.glb")
const GOLD := Color("f6c85f")

## Wheel-local geometry of the model, in metres (see assets/roulette/models).
const BALL_RADIUS_M := 0.015
const TRACK_RADIUS_M := 0.385
const RAMP_RADIUS_M := 0.306
const POCKET_RADIUS_M := 0.222
const TRACK_Y_M := 0.143
const RAMP_Y_M := 0.105
const POCKET_Y_M := 0.096

const IDLE_ROTOR_SPEED := 0.35
const SPIN_ROTOR_SPEED := 2.4
const BALL_START_SPEED := 9.0
const BALL_END_SPEED := 2.0
## Fraction of the spin after which the ball leaves the track and falls inward.
const DROP_START := 0.7
const SETTLE_S := 0.9
const BOUNCE_M := 0.012

var rotor: Node3D
var ball: Node3D

var _status: Label3D
var _caption: Label3D
var _last_state: Dictionary = {}
var _spin_id := -1
var _spin_elapsed := 0.0
var _settle_elapsed := 0.0
var _spinning := false
var _pocket := 0
var _ball_angle := 0.0
var _ball_radius := POCKET_RADIUS_M
var _rotor_speed := IDLE_ROTOR_SPEED

@onready var _table: RouletteTable = get_parent() as RouletteTable


func _ready() -> void:
	var model := MODEL.instantiate() as Node3D
	add_child(model)
	rotor = model.find_child("rotor", true, false) as Node3D
	ball = model.find_child("ball", true, false) as Node3D
	_status = _label("PLACE YOUR BETS", Vector3(0, 1.6, 0), 34, GOLD)
	_caption = _label("SPIN TO PLAY", Vector3(0, 1.37, 0), 26, Color.WHITE)
	_rest_in(0)


func _process(delta: float) -> void:
	var snapshot := _table.state
	if snapshot != _last_state:
		_last_state = snapshot.duplicate(true)
		_on_state(snapshot)
	animate(delta)


## Advances the wheel and ball by `delta` seconds.
func animate(delta: float) -> void:
	var target_speed := SPIN_ROTOR_SPEED if _spinning else IDLE_ROTOR_SPEED
	_rotor_speed = move_toward(_rotor_speed, target_speed, delta * 0.8)
	rotor.rotation.y = wrapf(rotor.rotation.y + _rotor_speed * delta, 0.0, TAU)
	var previous := ball.position
	if _spinning:
		_spin_elapsed += delta
		var t := clampf(_spin_elapsed / RouletteTable.SPIN_DURATION_S, 0.0, 1.0)
		_ball_angle -= lerpf(BALL_START_SPEED, BALL_END_SPEED, t) * delta
		var drop := clampf((t - DROP_START) / (1.0 - DROP_START), 0.0, 1.0)
		_ball_radius = lerpf(TRACK_RADIUS_M, RAMP_RADIUS_M, drop)
		_place_ball(_ball_angle, _ball_radius, 0.0)
	elif _settle_elapsed < SETTLE_S:
		_settle_elapsed += delta
		var s := smoothstep(0.0, 1.0, clampf(_settle_elapsed / SETTLE_S, 0.0, 1.0))
		_ball_angle -= BALL_END_SPEED * (1.0 - s) * delta
		var angle := lerp_angle(_ball_angle, pocket_angle(_pocket), s)
		var radius := lerpf(_ball_radius, POCKET_RADIUS_M, s)
		var hop := absf(sin(s * PI * 3.0)) * (1.0 - s) * BOUNCE_M
		_place_ball(angle, radius, hop)
	else:
		_place_ball(pocket_angle(_pocket), POCKET_RADIUS_M, 0.0)
		return
	_roll(ball.position - previous)


## Wheel-local angle of `number`'s pocket, following the rotor's current rotation.
func pocket_angle(number: int) -> float:
	var step := TAU / float(RouletteWheel.POCKET_COUNT)
	return RouletteWheel.wheel_index(number) * step - rotor.rotation.y


## Height of the ball's centre above the wheel origin when it rests at `radius`.
static func ball_height(radius: float) -> float:
	if radius >= RAMP_RADIUS_M:
		var t := (radius - RAMP_RADIUS_M) / (TRACK_RADIUS_M - RAMP_RADIUS_M)
		return lerpf(RAMP_Y_M, TRACK_Y_M, t)
	var u := clampf((radius - POCKET_RADIUS_M) / (RAMP_RADIUS_M - POCKET_RADIUS_M), 0.0, 1.0)
	return lerpf(POCKET_Y_M, RAMP_Y_M, u)


func _on_state(snapshot: Dictionary) -> void:
	var spin := int(snapshot["spin"])
	if snapshot["spinning"]:
		if spin != _spin_id:
			_start_spin(spin)
		_status.text = "SPINNING…"
		_caption.text = str(snapshot["operator"]).left(20)
		return
	var number := int(snapshot["number"])
	if spin > 0:
		if _spinning and spin == _spin_id:
			_settle_into(number)
		elif spin != _spin_id:
			# Joined after this spin finished: show the result without replaying it.
			_spin_id = spin
			_rest_in(number)
		var pocket := RouletteWheel.label_for(number)
		_status.text = "%s — %s" % [pocket, str(snapshot["color"]).to_upper()]
		_caption.text = str(snapshot["operator"]).left(20)
	else:
		_rest_in(0)
		_status.text = "PLACE YOUR BETS"
		_caption.text = "SPIN TO PLAY"


func _start_spin(spin: int) -> void:
	if not _spinning and _settle_elapsed >= SETTLE_S:
		_ball_angle = pocket_angle(_pocket)
	_spin_id = spin
	_spinning = true
	_spin_elapsed = 0.0


func _settle_into(number: int) -> void:
	_spinning = false
	_pocket = number
	_settle_elapsed = 0.0


func _rest_in(number: int) -> void:
	_spinning = false
	_pocket = number
	_settle_elapsed = SETTLE_S
	_ball_radius = POCKET_RADIUS_M
	_place_ball(pocket_angle(number), POCKET_RADIUS_M, 0.0)


func _place_ball(angle: float, radius: float, hop: float) -> void:
	ball.position = Vector3(sin(angle) * radius, ball_height(radius) + hop, -cos(angle) * radius)


## Rotates the ball as if it rolled along `step` without slipping.
func _roll(step: Vector3) -> void:
	step.y = 0.0
	var distance := step.length()
	if distance < 0.00001:
		return
	var axis := Vector3.UP.cross(step / distance)
	ball.basis = (Basis(axis, distance / BALL_RADIUS_M) * ball.basis).orthonormalized()


func _label(text: String, origin: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = origin
	label.font_size = font_size
	label.pixel_size = 0.003
	label.modulate = color
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	return label
