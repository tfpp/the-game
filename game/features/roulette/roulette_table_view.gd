class_name RouletteTableView
extends Node3D
## Table model, chips and spin presentation. Presentation only; never chooses results.
## Each peer animates the spin locally from the replicated snapshot: the rotor spins up,
## the ball orbits the track the other way and drops inward, and once the server settles
## the result the ball rolls into that pocket and rides the rotor. Every seated
## player's chips are drawn on the layout; the local seated player also gets the
## seated view (`roulette_seat_view.gd`) and, on request, the overhead betting screen
## (`roulette_betting_screen.gd`).

const MODEL := preload("res://assets/roulette/models/roulette_table.glb")
const BETTING_SCREEN := preload("res://features/roulette/roulette_betting_screen.gd")
const SEAT_VIEW := preload("res://features/roulette/roulette_seat_view.gd")
const GOLD := Color("f6c85f")
## Chip models, in RouletteBets.DENOMINATIONS order.
const CHIP_MODELS: Array[PackedScene] = [
	preload("res://assets/casino_chips/models/chip_1.glb"),
	preload("res://assets/casino_chips/models/chip_5.glb"),
	preload("res://assets/casino_chips/models/chip_50.glb"),
	preload("res://assets/casino_chips/models/chip_100.glb"),
	preload("res://assets/casino_chips/models/chip_500.glb"),
	preload("res://assets/casino_chips/models/chip_1000.glb"),
	preload("res://assets/casino_chips/models/chip_5000.glb"),
	preload("res://assets/casino_chips/models/chip_25000.glb"),
]
## Chips are drawn larger than life so they read from the overview camera.
const CHIP_SCALE := 2.2
const CHIP_HEIGHT_M := 0.0033 * CHIP_SCALE
const MAX_STACK := 12
## Each seat's chips sit slightly apart so shared spots stay readable.
const SEAT_OFFSET_M := 0.014

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
var chips: Node3D
var marker: MeshInstance3D
var screen: RouletteBettingScreen
var seat_view: RouletteSeatView
var chip_meshes: Array[Mesh] = []

var _status: Label3D
var _caption: Label3D
var _last_state: Dictionary = {}
var _last_seconds := -1
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
	for scene: PackedScene in CHIP_MODELS:
		var chip := scene.instantiate() as Node3D
		var mesh := chip.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		chip_meshes.append(mesh.mesh)
		chip.free()
	chips = Node3D.new()
	chips.name = "Chips"
	add_child(chips)
	marker = _winning_marker()
	add_child(marker)
	_status = _label("ROULETTE", Vector3(0, 1.6, 0), 34, GOLD)
	_caption = _label("", Vector3(0, 1.37, 0), 26, Color.WHITE)
	_rest_in(0)
	Network.mode_changed.connect(_on_mode_changed)
	RouletteSeatView.register_action()


func _process(delta: float) -> void:
	var snapshot := _table.state
	if snapshot != _last_state or _table.net_seconds_left != _last_seconds:
		_last_state = snapshot.duplicate(true)
		_last_seconds = _table.net_seconds_left
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
	_animate_wheel(snapshot)
	_update_labels(snapshot)
	_update_chips(snapshot)
	_update_screen(snapshot)


func _animate_wheel(snapshot: Dictionary) -> void:
	var spin := int(snapshot["spin"])
	if snapshot["spinning"]:
		if spin != _spin_id:
			_start_spin(spin)
		return
	if spin == 0:
		_rest_in(0)
		return
	var number := int(snapshot["number"])
	if _spinning and spin == _spin_id:
		_settle_into(number)
	elif spin != _spin_id:
		# Joined after this spin finished: show the result without replaying it.
		_spin_id = spin
		_rest_in(number)


func _update_labels(snapshot: Dictionary) -> void:
	var seated := (snapshot["seats"] as Array).count(0)
	seated = RouletteTable.SEAT_COUNT - seated
	var last := ""
	if int(snapshot["spin"]) > 0 and not snapshot["spinning"]:
		last = pocket_text(int(snapshot["number"]))
	match str(snapshot["phase"]):
		RouletteTable.PHASE_BETTING:
			_status.text = "PLACE YOUR BETS"
			_caption.text = (
				"%s  ·  %d/%d SEATED"
				% [clock_text(_table.net_seconds_left), seated, RouletteTable.SEAT_COUNT]
			)
		RouletteTable.PHASE_SPINNING:
			_status.text = "NO MORE BETS"
			_caption.text = ""
		RouletteTable.PHASE_RESULT:
			_status.text = last
			_caption.text = winners_text(snapshot)
		_:
			_status.text = "ROULETTE"
			_caption.text = str(snapshot["message"]) if snapshot["message"] else "UP TO 3 PLAYERS"
			if not last.is_empty():
				_caption.text += "  ·  LAST: " + last
	marker.visible = str(snapshot["phase"]) == RouletteTable.PHASE_RESULT
	if marker.visible:
		var anchor := RouletteBets.anchor(str(int(snapshot["number"])))
		marker.position = RouletteBets.pixel_to_local(anchor) + Vector3.UP * 0.026


## "17 RED", "00 GREEN".
static func pocket_text(number: int) -> String:
	return "%s %s" % [RouletteWheel.label_for(number), RouletteWheel.color_for(number).to_upper()]


## "0:42".
static func clock_text(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func winners_text(snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	var results := snapshot["results"] as Dictionary
	for peer: int in results:
		var result := results[peer] as Dictionary
		var won := int(result["payout"]) - int(result["wager"])
		if won > 0:
			var seat := (snapshot["seats"] as Array).find(peer)
			var name := str(snapshot["names"][seat]) if seat >= 0 else "A player"
			parts.append("%s +%s" % [name.left(14), PlayerMoney.format_money(won)])
	return ", ".join(parts) if not parts.is_empty() else "HOUSE WINS"


## Rebuilds the chip stacks: every seated player's placements, or, once the ball
## lands, only the winning spots (losing chips are swept).
func _update_chips(snapshot: Dictionary) -> void:
	for child: Node in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	var result_phase := str(snapshot["phase"]) == RouletteTable.PHASE_RESULT
	var number := int(snapshot["number"])
	var bets := snapshot["bets"] as Dictionary
	for peer: int in bets:
		var seat := maxi(0, (snapshot["seats"] as Array).find(peer))
		var stacks := RouletteBets.stacks(bets[peer])
		for key: String in stacks:
			if result_phase and not RouletteBets.numbers(key).has(number):
				continue
			var base := RouletteBets.pixel_to_local(RouletteBets.anchor(key))
			base.x += (seat - 1) * SEAT_OFFSET_M
			_stack(base, stacks[key])


## Chips in placement order, so the latest chip is always on top. Past MAX_STACK only
## the most recent chips are drawn.
func _stack(base: Vector3, placed: Array[int]) -> void:
	var values := placed.slice(maxi(0, placed.size() - MAX_STACK))
	for index: int in values.size():
		var chip := MeshInstance3D.new()
		chip.mesh = chip_meshes[RouletteBets.DENOMINATIONS.find(values[index])]
		chip.scale = Vector3.ONE * CHIP_SCALE
		chip.position = base + Vector3.UP * (index * CHIP_HEIGHT_M + 0.0005)
		chip.rotation.y = index * 0.7
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chips.add_child(chip)


## While the local player holds a seat they spectate from it (`RouletteSeatView`);
## the bet key opens the overhead betting screen. If the round releases them while
## that screen is open it stays up showing the result until they continue.
func _update_screen(snapshot: Dictionary) -> void:
	if not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return
	var seated := (snapshot["seats"] as Array).has(multiplayer.get_unique_id())
	if seated and seat_view == null:
		seat_view = SEAT_VIEW.new() as RouletteSeatView
		seat_view.table = _table
		seat_view.view = self
		add_child(seat_view)
	elif not seated and seat_view != null:
		seat_view.release()
		seat_view = null
	if screen != null:
		screen.refresh()
	if seat_view != null:
		seat_view.refresh()
	_show_labels()


## Opens the overhead betting screen for the seated local player.
func open_betting() -> void:
	if screen != null or seat_view == null:
		return
	screen = BETTING_SCREEN.new() as RouletteBettingScreen
	screen.table = _table
	screen.view = self
	screen.closed.connect(_on_screen_closed)
	add_child(screen)
	seat_view.refresh()
	_show_labels()


## The overhead screen shows the round itself, so the 3D labels would cover the felt.
func _show_labels() -> void:
	_status.visible = screen == null
	_caption.visible = screen == null


func _on_mode_changed(_mode: Network.Mode) -> void:
	if screen != null:
		screen.close()
	if seat_view != null:
		seat_view.release()
		seat_view = null


func _on_screen_closed() -> void:
	screen = null
	_show_labels()
	if seat_view != null:
		seat_view.refresh()


func _winning_marker() -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.02
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = GOLD
	material.metallic = 0.8
	material.roughness = 0.35
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "WinningMarker"
	node.mesh = mesh
	node.visible = false
	return node


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
