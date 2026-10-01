class_name MariachiMusicianModel
extends PatronModel
## A mariachi on the shared player avatar rig: black charro suit with silver
## buttons, white shirt, big red moño (bow tie) and a gold-trimmed black sombrero,
## playing a trumpet, violin, vihuela or guitarrón. Faces -Z, feet at the origin.
## Accessories and instruments are merged into one vertex-coloured mesh per rig
## pivot. Hands reach the instrument with the rig's arm IK and follow the song the
## band (`MariachiBand`) is playing: strums, bow strokes and raised trumpets.
## Cosmetic only: every peer poses its own copy, and only near the camera.

enum Instrument { TRUMPET, VIOLIN, VIHUELA, GUITARRON }

const SUIT := Color(0.06, 0.055, 0.065)
const SHIRT := Color(0.93, 0.92, 0.88)
const MONO := Color(0.72, 0.06, 0.1)
const MONO_KNOT := Color(0.48, 0.03, 0.06)
const SILVER := Color(0.82, 0.83, 0.86)
const GOLD := Color(0.86, 0.66, 0.24)
const FELT := Color(0.07, 0.06, 0.06)
const BRASS := Color(0.88, 0.68, 0.26)
const BRASS_DARK := Color(0.62, 0.45, 0.16)
const SPRUCE := Color(0.84, 0.64, 0.37)
const ROSEWOOD := Color(0.33, 0.15, 0.07)
const EBONY := Color(0.07, 0.05, 0.04)
const VIOLIN_WOOD := Color(0.58, 0.24, 0.08)
const BOW_HAIR := Color(0.88, 0.85, 0.76)

## Skin, hair and moustache per musician (`look`), dressed in the same suit.
const MUSICIANS: Array[Dictionary] = [
	{"skin": 3, "hair": "crop", "hair_color": 0, "moustache": true},
	{"skin": 4, "hair": "classic", "hair_color": 0, "moustache": false},
	{"skin": 2, "hair": "crop", "hair_color": 4, "moustache": true},
	{"skin": 5, "hair": "classic", "hair_color": 0, "moustache": true},
	{"skin": 3, "hair": "swept", "hair_color": 1, "moustache": false},
]

## Pose updates at most this often, and not at all beyond `POSE_RANGE_M` of the camera.
const UPDATE_S := 1.0 / 30.0
const POSE_RANGE_M := 32.0
## Seconds to raise or lower a trumpet or bow between phrases.
const RAISE_S := 0.35
const MATERIAL := preload("res://features/mariachi_band/vertex_color.tres")

## Instruments in the torso pivot's space (the waist, facing -Z). The trumpet's
## playing pose puts its mouthpiece on the rig's lips (head pivot +0.65 m, mouth
## 0.142 m above and 0.08 m in front of it).
const MOUTH := Vector3(0, 0.792, -0.09)
const TRUMPET_PLAY := Transform3D(Basis(Vector3.RIGHT, -0.12), MOUTH)
const TRUMPET_REST := Transform3D(Basis(Vector3.RIGHT, -0.95), Vector3(0.02, 0.42, -0.24))

@export var instrument := Instrument.TRUMPET
@export var look := 0
## Offsets this musician's idle motion so the band doesn't sway in lockstep.
@export var seed_phase := 0.0

var band: MariachiBand
var _time := 0.0
var _since := UPDATE_S
var _raised := 1.0
## Moving parts: the trumpet or violin bow (separate meshes), and the instrument
## frame hands reach for (in torso space).
var _horn: MeshInstance3D
var _bow: MeshInstance3D
var _frame := Transform3D.IDENTITY


func _ready() -> void:
	var data: Dictionary = MUSICIANS[posmod(look, MUSICIANS.size())]
	dress_up(
		{
			"skin": data["skin"],
			"hair": data["hair"],
			"hair_color": data["hair_color"],
			"shirt": 1,
			"pants": 1,
			"tie": -1,
		}
	)
	var surface := avatar.human.material
	surface.set_shader_parameter("shirt_tint", SUIT)
	surface.set_shader_parameter("pants_tint", SUIT)
	_dress(bool(data["moustache"]))
	_build_instrument()
	band = find_band(self)
	_time = seed_phase
	_update(0.0)


func _process(delta: float) -> void:
	_time += delta
	_since += delta
	if _since < UPDATE_S or not is_visible_in_tree() or not _near_camera():
		return
	_update(_since)
	_since = 0.0


## The nearest `MariachiBand` above `node`, or null for a standalone musician.
static func find_band(node: Node) -> MariachiBand:
	var parent := node.get_parent()
	while parent != null and not parent is MariachiBand:
		parent = parent.get_parent()
	return parent as MariachiBand


## Hitbox in this node's space, wide enough for the sombrero brim and instrument.
func hitbox_bounds() -> AABB:
	return AABB(Vector3(-0.38, 0.0, -0.55), Vector3(0.76, 1.95, 0.85))


## True while this musician's part of the tune is sounding (accompanists always play).
static func playing(part: Instrument, song: int, time: float) -> bool:
	var lead := MariachiSongs.lead_at(song, time)
	match part:
		Instrument.TRUMPET:
			return lead == MariachiSongs.Voice.TRUMPET
		Instrument.VIOLIN:
			return lead == MariachiSongs.Voice.VIOLIN
	return true


## How far (metres, along the strings) the strumming hand has dropped `since`
## seconds after a strum: a quick stroke, then a slower recovery.
static func strum_offset(since: float) -> float:
	if since < 0.05:
		return -0.07 * since / 0.05
	return -0.07 * maxf(0.0, 1.0 - (since - 0.05) / 0.2)


## Bow travel (0 at the frog, 1 at the tip) for the melody note `note`
## ([index, fraction]); strokes alternate up and down with each note.
static func bow_travel(note: Vector2) -> float:
	var stroke := clampf(note.y, 0.0, 1.0)
	return stroke if int(note.x) % 2 == 0 else 1.0 - stroke


func _near_camera() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	var range_m := POSE_RANGE_M
	return camera.global_position.distance_squared_to(global_position) < range_m * range_m


func _update(delta: float) -> void:
	var song := 0
	var time := _time
	var live := false
	if band != null:
		song = band.net_song
		time = band.song_time()
		live = band.band_awake()
	var unit := MariachiSongs.unit_s(song)
	var beat := time / (unit * 2.0)
	pose(delta, 0.0, 0.0, 0.0, _time)
	# Sway on the beat; the head keeps still for the trumpets and violin.
	var sway := sin(beat * PI + seed_phase) if live else sin(_time * 0.8 + seed_phase) * 0.4
	avatar._torso.rotation = Vector3(-0.03, sway * 0.04, sway * 0.035)
	if instrument != Instrument.VIHUELA and instrument != Instrument.GUITARRON:
		avatar._head.rotation = Vector3(0.0, 0.0, -sway * 0.02)
	else:
		avatar._head.rotation = Vector3(0.05, sin(_time * 0.5 + seed_phase) * 0.3, 0.0)
	avatar.human.pose(avatar, false, false)
	var target := 1.0 if live and playing(instrument, song, time) else 0.0
	_raised = move_toward(_raised, target, delta / RAISE_S) if delta > 0.0 else target
	match instrument:
		Instrument.TRUMPET:
			_play_trumpet(time, song)
		Instrument.VIOLIN:
			_play_violin(song, time)
		_:
			_play_strings(song, time, live)


func _play_trumpet(time: float, song: int) -> void:
	var raised := smoothstep(0.0, 1.0, _raised)
	var note := MariachiSongs.note_at(song, time)
	var lift := 0.025 * raised * (1.0 - note.y) if int(note.x) % 2 == 0 else 0.0
	var pose_at := TRUMPET_REST.interpolate_with(TRUMPET_PLAY, raised)
	pose_at = pose_at.rotated_local(Vector3.RIGHT, lift)
	_horn.transform = pose_at
	_grip(true, _horn.global_transform * Vector3(0.03, 0.035, -0.12), 0.55)
	_grip(false, _horn.global_transform * Vector3(-0.035, -0.05, -0.19), 0.85)


func _play_violin(song: int, time: float) -> void:
	var raised := smoothstep(0.0, 1.0, _raised)
	var travel := bow_travel(MariachiSongs.note_at(song, time)) if raised > 0.5 else 0.3
	var contact := _frame * Vector3(0.0, -0.09, -0.05)
	var across := (_frame.basis * Vector3(1, 0, 0)).normalized()
	var playing_frog := contact + across * lerpf(0.12, 0.5, travel)
	var resting_frog := Vector3(0.28, 0.12, -0.12)
	var frog := resting_frog.lerp(playing_frog, raised)
	var along := (-across).lerp(Vector3(-0.15, 1.0, -0.4).normalized(), 1.0 - raised).normalized()
	_bow.transform = Transform3D(_basis_along(along), frog)
	var torso := avatar._torso.global_transform
	_grip(false, torso * (_frame * Vector3(0.02, 0.25, 0.04)), 0.8)
	_grip(true, torso * (frog - along * 0.06 + Vector3(0, 0.02, 0)), 0.55)


func _play_strings(song: int, time: float, live: bool) -> void:
	var torso := avatar._torso.global_transform
	var neck := 0.48 if instrument == Instrument.VIHUELA else 0.62
	var since := MariachiSongs.since_hit(song, time, "strum")
	if instrument == Instrument.GUITARRON:
		since = MariachiSongs.since_hit(song, time, "bass")
	var stroke := strum_offset(since) if live else 0.0
	var hole := Vector3(0.0, 0.03 + stroke, -0.12)
	if instrument == Instrument.GUITARRON:
		hole = Vector3(0.0, 0.05 + stroke * 0.6, -0.18)
	_grip(false, torso * (_frame * Vector3(0.0, neck, 0.06)), 0.75)
	_grip(true, torso * (_frame * hole), 0.45)


func _grip(right: bool, world: Vector3, curl: float) -> void:
	avatar.human.reach_grip(right, world)
	avatar.human.set_finger_curl(right, curl)


## A basis whose Y axis points along `direction`.
static func _basis_along(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.UP)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _dress(moustache: bool) -> void:
	var torso := MariachiMeshKit.new()
	# White shirt front, the big red moño and the jacket's silver buttons.
	torso.box(
		Transform3D(Basis(), Vector3(0, 0.47, CHEST_Z + 0.006)), Vector3(0.11, 0.17, 0.012), SHIRT
	)
	torso.box(
		Transform3D(Basis(), Vector3(0, 0.545, CHEST_Z - 0.008)), Vector3(0.21, 0.065, 0.02), MONO
	)
	torso.box(
		Transform3D(Basis(), Vector3(0, 0.545, CHEST_Z - 0.02)),
		Vector3(0.045, 0.05, 0.016),
		MONO_KNOT
	)
	for side: float in [-1.0, 1.0]:
		for row: int in 3:
			var at := Vector3(side * 0.085, 0.29 + row * 0.055, CHEST_Z - 0.002)
			torso.box(Transform3D(Basis(), at), Vector3(0.02, 0.02, 0.012), SILVER)
	_instance("Suit", torso_items, torso)
	var head := MariachiMeshKit.new()
	_sombrero(head)
	if moustache:
		var hair := PlayerAppearance.HAIR_COLORS[0]
		head.box(
			Transform3D(Basis(), Vector3(0, 0.152, FACE_Z + 0.003)),
			Vector3(0.095, 0.02, 0.014),
			hair
		)
		for side: float in [-1.0, 1.0]:
			var tip := Vector3(side * 0.045, 0.132, FACE_Z + 0.004)
			head.box(Transform3D(Basis(), tip), Vector3(0.016, 0.04, 0.012), hair)
	_instance("Sombrero", head_items, head)
	# Botonadura: a row of silver buttons down the outside of each trouser leg.
	for side: float in [-1.0, 1.0]:
		var leg := avatar._left_leg if side < 0.0 else avatar._right_leg
		var shin := avatar._left_shin if side < 0.0 else avatar._right_shin
		for part: Node3D in [leg, shin]:
			var kit := MariachiMeshKit.new()
			for row: int in 4:
				var at := Vector3(side * 0.082, -0.05 - row * 0.08, 0.0)
				kit.box(Transform3D(Basis(), at), Vector3(0.012, 0.022, 0.022), SILVER)
			var holder := _pivot("Accessories", part, Vector3.ZERO)
			_instance("Botonadura", holder, kit)


func _sombrero(kit: MariachiMeshKit) -> void:
	# A wide, upturned brim, a tall crown and gold trim, sitting low on the head.
	kit.cylinder(Transform3D(Basis(), Vector3(0, 0.272, 0.01)), 0.37, 0.3, 0.045, FELT, 14)
	kit.ring(Transform3D(Basis(), Vector3(0, 0.297, 0.01)), 0.35, 0.385, GOLD, 16)
	kit.cylinder(Transform3D(Basis(), Vector3(0, 0.39, 0.01)), 0.075, 0.115, 0.21, FELT, 10)
	kit.cylinder(Transform3D(Basis(), Vector3(0, 0.316, 0.01)), 0.113, 0.118, 0.05, GOLD, 10)


func _build_instrument() -> void:
	var kit := MariachiMeshKit.new()
	match instrument:
		Instrument.TRUMPET:
			_trumpet(kit)
			_horn = _instance("Trumpet", torso_items, kit)
			_horn.transform = TRUMPET_PLAY
			return
		Instrument.VIOLIN:
			# Under the chin on the left shoulder, scroll forward-left, top facing up.
			var neck := Vector3(-0.42, -0.12, -0.9).normalized()
			var face := Vector3(0.25, -1.0, 0.05)
			var x := neck.cross(face).normalized()
			_frame = Transform3D(Basis(x, neck, x.cross(neck)), Vector3(-0.17, 0.7, -0.22))
			_violin(kit)
			var bow := MariachiMeshKit.new()
			bow.box(
				Transform3D(Basis(), Vector3(0, 0.31, 0)), Vector3(0.009, 0.64, 0.009), ROSEWOOD
			)
			bow.box(
				Transform3D(Basis(), Vector3(0, 0.31, 0.014)), Vector3(0.014, 0.6, 0.004), BOW_HAIR
			)
			bow.box(Transform3D(Basis(), Vector3(0, 0.0, 0.01)), Vector3(0.016, 0.05, 0.022), EBONY)
			_bow = _instance("Bow", torso_items, bow)
		Instrument.VIHUELA:
			_frame = _held(0.75, Vector3(0.08, 0.27, -0.19))
			_guitar(kit, 1.0, 0.09)
		_:
			_frame = _held(0.62, Vector3(0.05, 0.2, -0.28))
			_guitar(kit, 1.75, 0.22)
	var holder := Node3D.new()
	holder.name = "Instrument"
	holder.transform = _frame
	torso_items.add_child(holder)
	_instance("Body", holder, kit)


## A guitar-shaped frame held across the belly with the neck rising to the left.
static func _held(tilt: float, at: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, tilt) * Basis(Vector3.UP, 0.15), at)


## Guitar-family body in instrument space: +Y up the neck, -Z out of the soundboard.
func _guitar(kit: MariachiMeshKit, size: float, depth: float) -> void:
	var lying := Basis(Vector3.RIGHT, PI / 2.0)
	var top_z := -depth * 0.5 - 0.003
	for bout: Vector2 in [Vector2(-0.05, 0.15), Vector2(0.14, 0.115)]:
		var at := Vector3(0, bout.x * size, 0)
		kit.cylinder(Transform3D(lying, at), bout.y * size, bout.y * size, depth, ROSEWOOD, 12)
		var face := Vector3(0, bout.x * size, top_z)
		kit.cylinder(
			Transform3D(lying, face),
			bout.y * size - 0.006,
			bout.y * size - 0.006,
			0.006,
			SPRUCE,
			12
		)
	kit.cylinder(
		Transform3D(lying, Vector3(0, 0.06 * size, top_z - 0.002)),
		0.038 * size,
		0.038 * size,
		0.004,
		EBONY,
		10
	)
	kit.box(
		Transform3D(Basis(), Vector3(0, -0.11 * size, top_z - 0.006)),
		Vector3(0.1 * size, 0.02, 0.01),
		EBONY
	)
	var neck_length := 0.36 if size < 1.2 else 0.42
	var neck_start := 0.24 * size
	var neck_mid := neck_start + neck_length * 0.5
	kit.box(
		Transform3D(Basis(), Vector3(0, neck_mid, -0.01)),
		Vector3(0.05, neck_length, 0.03),
		ROSEWOOD
	)
	kit.box(
		Transform3D(Basis(), Vector3(0, neck_mid, -0.027)),
		Vector3(0.046, neck_length, 0.005),
		EBONY
	)
	kit.box(
		Transform3D(Basis(), Vector3(0, neck_start + neck_length + 0.06, -0.005)),
		Vector3(0.075, 0.13, 0.025),
		ROSEWOOD
	)


func _violin(kit: MariachiMeshKit) -> void:
	var lying := Basis(Vector3.RIGHT, PI / 2.0)
	kit.cylinder(Transform3D(lying, Vector3(0, -0.06, 0)), 0.1, 0.1, 0.045, VIOLIN_WOOD, 12)
	kit.cylinder(Transform3D(lying, Vector3(0, 0.07, 0)), 0.085, 0.085, 0.045, VIOLIN_WOOD, 12)
	kit.box(Transform3D(Basis(), Vector3(0, 0.0, -0.026)), Vector3(0.05, 0.08, 0.008), VIOLIN_WOOD)
	kit.box(Transform3D(Basis(), Vector3(0, 0.15, -0.032)), Vector3(0.026, 0.22, 0.012), EBONY)
	kit.box(Transform3D(Basis(), Vector3(0, 0.3, -0.01)), Vector3(0.03, 0.06, 0.03), VIOLIN_WOOD)
	kit.box(Transform3D(Basis(), Vector3(0, -0.15, -0.03)), Vector3(0.07, 0.05, 0.015), EBONY)
	kit.box(Transform3D(Basis(), Vector3(0, -0.04, -0.03)), Vector3(0.05, 0.012, 0.02), SPRUCE)


## Trumpet in its own space: mouthpiece at the origin, bell toward -Z.
func _trumpet(kit: MariachiMeshKit) -> void:
	var along := Basis(Vector3.RIGHT, PI / 2.0)
	var flare := Basis(Vector3.RIGHT, -PI / 2.0)
	kit.cylinder(Transform3D(along, Vector3(0, 0, -0.03)), 0.012, 0.006, 0.06, BRASS_DARK, 8)
	kit.cylinder(Transform3D(along, Vector3(0, 0, -0.23)), 0.009, 0.009, 0.36, BRASS, 8)
	kit.cylinder(Transform3D(flare, Vector3(0, 0, -0.47)), 0.065, 0.012, 0.14, BRASS, 14)
	kit.cylinder(Transform3D(along, Vector3(0, -0.05, -0.22)), 0.008, 0.008, 0.28, BRASS, 8)
	kit.box(Transform3D(Basis(), Vector3(0, -0.025, -0.19)), Vector3(0.026, 0.08, 0.075), BRASS)
	for valve: int in 3:
		var cap := Vector3(0, 0.025, -0.165 - valve * 0.025)
		kit.cylinder(Transform3D(Basis(), cap), 0.01, 0.01, 0.03, BRASS_DARK, 8)


func _instance(label: String, parent: Node3D, kit: MariachiMeshKit) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = kit.commit()
	part.material_override = MATERIAL
	parent.add_child(part)
	return part
