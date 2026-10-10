class_name DiscoParty
extends Node3D
## DJ booth in the gaming pit. Anyone can drop the beat: the server starts a
## PARTY_S party for the whole casino (spinning mirror ball, colored beams, a
## pulsing light and a synthesized disco loop), then the booth recharges.
## The feature root is the booth; the ball hangs over the pit centre.

const PARTY_S := 30.0
const RECHARGE_S := 45.0
const USE_RANGE := 2.5
## Booth plinth footprint and height (metres, local to the root).
const BOOTH_SIZE := Vector3(1.2, 1.0, 0.6)
## Mirror ball centre in global space and the main hall ceiling above it.
const BALL_GLOBAL := Vector3(0, 6.5, 0)
const BALL_RADIUS := 0.6
const CEILING_Y := 8.75
const BEAM_COUNT := 6
const BEAM_LENGTH := 7.0
const COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.6),
	Color(0.2, 0.6, 1.0),
	Color(1.0, 0.85, 0.2),
	Color(0.3, 1.0, 0.4),
	Color(0.7, 0.3, 1.0),
	Color(1.0, 0.45, 0.1),
]

## Whole seconds of party left; 0 when quiet. Replicated on change.
@export var net_seconds_left := 0
## Whole seconds until the booth can be used again. Replicated on change.
@export var net_recharge_left := 0
## Name of whoever dropped the current beat.
@export var net_dj := ""

var _party_left := 0.0
var _recharge_left := 0.0
var _clock := 0.0
var _ball: Node3D
var _beams: Node3D
var _beam_materials: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _sign: Label3D
var _audio: AudioStreamPlayer3D

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"disco_party")
	entity.interaction_range = USE_RANGE
	entity.interaction_offset = Vector3(0, 0.9, 0)
	entity.register_use(can_use, _start_party)
	entity.session_reset.connect(_reset)
	_build_booth()
	_build_ball()
	_present(0.0)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		advance(delta)
	_present(delta)


func is_partying() -> bool:
	return net_seconds_left > 0


func can_use(player: Player) -> bool:
	return entity.in_range(player) and net_seconds_left == 0 and net_recharge_left == 0


func interaction_text() -> String:
	return "Drop the beat (%ds disco party)" % int(PARTY_S)


func interaction_color() -> Color:
	return COLORS[0]


func use() -> void:
	entity.request_use()


## Server: run the party and recharge clocks.
func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _party_left > 0.0:
		_party_left = maxf(_party_left - delta, 0.0)
		if _party_left == 0.0:
			_recharge_left = RECHARGE_S
			net_dj = ""
	elif _recharge_left > 0.0:
		_recharge_left = maxf(_recharge_left - delta, 0.0)
	_publish()


## What the booth sign shows for a given replicated state.
static func sign_text(seconds_left: int, recharge_left: int, dj: String) -> String:
	if seconds_left > 0:
		return "%s IS ON THE DECKS\n%ds" % [dj.to_upper(), seconds_left]
	if recharge_left > 0:
		return "DISCO RECHARGING\n%ds" % recharge_left
	return "DISCO PARTY\nPRESS USE"


func _start_party(player: Player) -> bool:
	if _party_left > 0.0 or _recharge_left > 0.0:
		return false
	_party_left = PARTY_S
	net_dj = player.display_name if not player.display_name.is_empty() else "A guest"
	_publish()
	return true


func _publish() -> void:
	var seconds := ceili(_party_left)
	var recharge := ceili(_recharge_left)
	if seconds != net_seconds_left:
		net_seconds_left = seconds
	if recharge != net_recharge_left:
		net_recharge_left = recharge


func _reset(_mode: Network.Mode) -> void:
	_party_left = 0.0
	_recharge_left = 0.0
	net_dj = ""
	_publish()


func _present(delta: float) -> void:
	var active := is_partying()
	_clock += delta
	_sign.text = sign_text(net_seconds_left, net_recharge_left, net_dj)
	_ball.rotate_y(delta * (2.4 if active else 0.25))
	_beams.visible = active
	_light.visible = active
	if active:
		_beams.rotation.y = -_clock * 0.9
		var pulse := 0.5 + 0.5 * cos(fmod(_clock, 0.5) / 0.5 * TAU)
		_light.light_color = COLORS[int(_clock * 2.0) % COLORS.size()]
		_light.light_energy = 1.2 + pulse * 1.6
		for index: int in _beam_materials.size():
			var color := COLORS[(index + int(_clock * 2.0)) % COLORS.size()]
			color.a = 0.18 + 0.12 * pulse
			_beam_materials[index].albedo_color = color
	_update_audio(active)


func _update_audio(active: bool) -> void:
	if not MariachiBand.audible():
		return
	if active and not _audio.playing:
		if _audio.stream == null:
			_audio.stream = DiscoBeat.build()
		_audio.play()
	elif not active and _audio.playing:
		_audio.stop()


func _build_booth() -> void:
	var walnut := StandardMaterial3D.new()
	walnut.albedo_color = Color(0.18, 0.1, 0.07)
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var box := BoxMesh.new()
	box.size = BOOTH_SIZE
	box.material = walnut
	plinth.mesh = box
	plinth.position.y = BOOTH_SIZE.y / 2.0
	add_child(plinth)
	# Gold trim band and two turntables on the deck.
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.2)
	gold.metallic = 0.6
	var trim := MeshInstance3D.new()
	var trim_mesh := BoxMesh.new()
	trim_mesh.size = Vector3(BOOTH_SIZE.x + 0.02, 0.06, BOOTH_SIZE.z + 0.02)
	trim_mesh.material = gold
	trim.mesh = trim_mesh
	trim.position.y = BOOTH_SIZE.y - 0.03
	add_child(trim)
	var vinyl := StandardMaterial3D.new()
	vinyl.albedo_color = Color(0.05, 0.05, 0.06)
	for side: float in [-0.3, 0.3]:
		var deck := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.17
		disc.bottom_radius = 0.17
		disc.height = 0.03
		disc.radial_segments = 12
		disc.material = vinyl
		deck.mesh = disc
		deck.position = Vector3(side, BOOTH_SIZE.y + 0.015, 0)
		add_child(deck)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.08, 0.1)
	red.emission_enabled = true
	red.emission = Color(0.6, 0.0, 0.05)
	var button := MeshInstance3D.new()
	button.name = "Button"
	var dome := SphereMesh.new()
	dome.radius = 0.08
	dome.height = 0.08
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 3
	dome.material = red
	button.mesh = dome
	button.position = Vector3(0, BOOTH_SIZE.y, 0)
	add_child(button)
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = BOOTH_SIZE
	shape.shape = box_shape
	shape.position.y = BOOTH_SIZE.y / 2.0
	body.add_child(shape)
	add_child(body)
	_sign = Label3D.new()
	_sign.name = "Sign"
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.pixel_size = 0.004
	_sign.font_size = 48
	_sign.outline_size = 12
	_sign.modulate = Color(1.0, 0.85, 0.3)
	_sign.position.y = BOOTH_SIZE.y + 0.55
	add_child(_sign)


func _build_ball() -> void:
	_ball = Node3D.new()
	_ball.name = "Ball"
	add_child(_ball)
	_ball.global_position = BALL_GLOBAL
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color(0.85, 0.87, 0.9)
	mirror.metallic = 0.9
	mirror.roughness = 0.15
	mirror.emission_enabled = true
	mirror.emission = Color(0.25, 0.25, 0.3)
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 14
	sphere.rings = 7
	sphere.material = mirror
	var ball_mesh := MeshInstance3D.new()
	ball_mesh.name = "Mirror"
	ball_mesh.mesh = sphere
	_ball.add_child(ball_mesh)
	var cable := MeshInstance3D.new()
	cable.name = "Cable"
	var cord := CylinderMesh.new()
	var cable_length := CEILING_Y - (BALL_GLOBAL.y + BALL_RADIUS)
	cord.top_radius = 0.015
	cord.bottom_radius = 0.015
	cord.height = cable_length
	cord.radial_segments = 4
	cord.material = mirror
	cable.mesh = cord
	add_child(cable)
	cable.global_position = Vector3(BALL_GLOBAL.x, CEILING_Y - cable_length / 2.0, BALL_GLOBAL.z)
	_beams = Node3D.new()
	_beams.name = "Beams"
	add_child(_beams)
	_beams.global_position = BALL_GLOBAL
	for index: int in BEAM_COUNT:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = COLORS[index]
		_beam_materials.append(material)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.6
		cone.height = BEAM_LENGTH
		cone.radial_segments = 8
		cone.cap_top = false
		cone.cap_bottom = false
		cone.material = material
		var pivot := Node3D.new()
		pivot.rotation = Vector3(0, index * TAU / BEAM_COUNT, deg_to_rad(-58))
		var beam := MeshInstance3D.new()
		beam.mesh = cone
		beam.position.y = -BEAM_LENGTH / 2.0
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(beam)
		_beams.add_child(pivot)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.omni_range = 16.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = BALL_GLOBAL + Vector3.DOWN * 1.0
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Beat"
	_audio.max_distance = 40.0
	_audio.unit_size = 8.0
	_audio.volume_db = -4.0
	if AudioServer.get_bus_index(GameAudio.BUS) >= 0:
		_audio.bus = GameAudio.BUS
	add_child(_audio)
	_audio.global_position = BALL_GLOBAL
