extends Node3D
## Seeded fluorescent ceiling tubes for one garage deck. Lower decks lose more tubes.
## Flicker, hum and light levels are local presentation derived from the shared seed.

const SYNTH := preload("res://features/parking_garage/procedural_audio.gd")
const ROOF_Y := 3.44
## Tubes hang over the four deck strips around the atrium (x -10..10, z 12..30).
const SLOTS: Array[Vector3] = [
	Vector3(-15, ROOF_Y, 6),
	Vector3(-5, ROOF_Y, 6),
	Vector3(5, ROOF_Y, 6),
	Vector3(15, ROOF_Y, 6),
	Vector3(-15.5, ROOF_Y, 17),
	Vector3(15.5, ROOF_Y, 17),
	Vector3(-15.5, ROOF_Y, 25),
	Vector3(15.5, ROOF_Y, 25),
	Vector3(-15, ROOF_Y, 36),
	Vector3(-5, ROOF_Y, 36),
	Vector3(5, ROOF_Y, 36),
	Vector3(15, ROOF_Y, 36)
]
## Each deck lights its south and north rows from the tube nearest the centre line.
const LIT_SLOTS: Array[int] = [2, 9]
const TUBE_COLOR := Color("d8f0ff")
const ACTIVE_RANGE := 28.0
const UPDATE_SECONDS := 0.05
const ACTIVE_HEIGHT := 4.0
static var _hum_stream: AudioStreamWAV

var tubes: Array[MeshInstance3D] = []
var states: Array[String] = []
var phases: Array[float] = []
var lights: Array[OmniLight3D] = []
var hums: Array[AudioStreamPlayer3D] = []
var light_energy := 0.8
var _elapsed := 0.0


## Deterministic tube states: "steady", "flicker" or "dead". Index 4 is B1, 0 is B5.
static func plan(floor_index: int, seed_value: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + floor_index * 7919
	var broken := 0.1 + (4 - floor_index) * 0.08
	var result: Array[String] = []
	for slot: int in SLOTS.size():
		var roll := rng.randf()
		if slot in LIT_SLOTS:
			# Lit tubes never die, so every deck keeps readable pools of light.
			result.append("flicker" if roll < 0.35 + broken else "steady")
		elif roll < broken:
			result.append("dead")
		elif roll < broken + 0.25:
			result.append("flicker")
		else:
			result.append("steady")
	return result


## Brightness (0..1) of a flickering tube at time t. Short stutters every few seconds.
static func flicker_level(t: float, phase: float) -> float:
	var local := fmod(t + phase * 11.0, 6.0 + phase * 5.0)
	if local > 0.9:
		return 1.0
	var step := int(local * 22.0 + phase * 97.0)
	return 0.06 if posmod(step * 7919, 7) < 3 else 1.0


func build(floor_index: int, seed_value: int) -> void:
	states = plan(floor_index, seed_value)
	light_energy = 0.55 + floor_index * 0.1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + floor_index * 31
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.05, 0.14)
	var lit := _tube_material(true)
	var dead := _tube_material(false)
	for slot: int in SLOTS.size():
		var tube := MeshInstance3D.new()
		tube.name = "Tube%d" % slot
		tube.mesh = mesh
		tube.position = SLOTS[slot]
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var state := states[slot]
		# Flickering tubes own their material so they can dim independently.
		tube.material_override = (
			dead if state == "dead" else (_tube_material(true) if state == "flicker" else lit)
		)
		add_child(tube)
		tubes.append(tube)
		phases.append(rng.randf())
	for slot: int in LIT_SLOTS:
		var light := OmniLight3D.new()
		light.name = "Light%d" % slot
		light.position = SLOTS[slot] + Vector3(0, -0.3, 0)
		light.light_color = TUBE_COLOR
		light.light_energy = light_energy
		light.omni_range = 12
		light.omni_attenuation = 1.4
		add_child(light)
		lights.append(light)
	if Network.mode == Network.Mode.SERVER:
		return
	if _hum_stream == null:
		_hum_stream = SYNTH.hum_loop(120, 6021)
	for slot: int in LIT_SLOTS:
		var hum := AudioStreamPlayer3D.new()
		hum.name = "Hum%d" % slot
		hum.stream = _hum_stream
		hum.bus = GameAudio.BUS
		hum.volume_db = -30
		hum.unit_size = 2
		hum.max_distance = 11
		hum.position = SLOTS[slot]
		add_child(hum)
		hums.append(hum)


func _tube_material(on: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = TUBE_COLOR if on else Color("3a4046")
	if on:
		material.emission_enabled = true
		material.emission = TUBE_COLOR
		material.emission_energy_multiplier = 2.0
	return material


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_SECONDS:
		return
	_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	var active := camera != null and camera_is_near(camera.global_position)
	for light: OmniLight3D in lights:
		light.visible = active
	var beacon := get_parent().get_node_or_null("ElevatorBeacon") as OmniLight3D
	if beacon != null:
		beacon.visible = active
	for hum: AudioStreamPlayer3D in hums:
		if active and not hum.playing:
			hum.play()
		elif not active and hum.playing:
			hum.stop()
	if active:
		apply_time(Time.get_ticks_msec() / 1000.0)


## Only the current deck and its immediate vertical neighbours need dynamic lights.
func camera_is_near(point: Vector3) -> bool:
	var local := to_local(point)
	return (
		absf(local.y - 2.0) <= ACTIVE_HEIGHT
		and Vector2(local.x, local.z - 21).length_squared() < ACTIVE_RANGE * ACTIVE_RANGE
	)


## Sets every tube, light and hum to its level at time t.
func apply_time(t: float) -> void:
	for slot: int in tubes.size():
		if states[slot] != "flicker":
			continue
		var level := flicker_level(t, phases[slot])
		var material := tubes[slot].material_override as StandardMaterial3D
		material.emission_energy_multiplier = 2.0 * level
		var lit := LIT_SLOTS.find(slot)
		if lit >= 0:
			lights[lit].light_energy = light_energy * level
			if lit < hums.size():
				hums[lit].volume_db = -30 if level > 0.5 else -44
