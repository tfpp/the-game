class_name DayNight
extends Node3D
## A shared world clock, not server-authoritative state: every peer derives the same
## time of day from Time.get_unix_time_from_system(), the same real-world clock
## features/money/money.gd and core/net/network.gd already key off of, so the sun and
## sky stay in sync across peers without any RPC or MultiplayerSynchronizer. There is
## nothing here for a player to change, only a shared read of the wall clock.
##
## The lone WorldEnvironment lives in world/room.tscn (see game/AGENTS.md: features
## shouldn't edit world/ to wire themselves in), so this feature finds it locally on
## each peer with get_tree().root.find_children(), the same read-only lookup pattern
## features/ui_sounds/ui_sounds.gd already uses for local nodes outside its own tree.

## One full day/night cycle, in real seconds: 48 real-time minutes per the request.
const DAY_LENGTH_SECONDS := 48.0 * 60.0

## Sun elevation (degrees) at and below which it's full night, and at and above which
## it's full day. Between them is a smooth dawn/dusk twilight ramp.
const NIGHT_ELEVATION_DEG := -6.0
const DAY_ELEVATION_DEG := 20.0

## Fixed compass heading for the sun's path; only its elevation animates.
const SUN_AZIMUTH_DEG := 35.0

const NIGHT_SUN_ENERGY := 0.45
const DAY_SUN_ENERGY := 1.0
const NIGHT_SUN_COLOR := Color(0.55, 0.65, 0.9)
const DAY_SUN_COLOR := Color(1.0, 0.96, 0.88)

## Keep dark materials and player silhouettes readable even where a fixture fails.
## The old values multiplied to near-black before local lights were considered.
const NIGHT_AMBIENT_COLOR := Color(0.69, 0.73, 0.81)
const NIGHT_AMBIENT_ENERGY := 0.75
const NIGHT_SKY_ENERGY_MULTIPLIER := 0.42

const DAY_SKY_TEXTURE := preload("res://assets/kenney/skyboxes/skybox-day.png")
const NIGHT_SKY_TEXTURE := preload("res://assets/kenney/skyboxes/skybox-night.png")
const SKY_SHADER := preload("res://features/day_night/day_night_sky.gdshader")

## The world's WorldEnvironment resource, if one was found; left null (skipping all
## sky/ambient changes) when this runs without one, e.g. standalone in tests.
var _environment: Environment
var _sky_material: ShaderMaterial
var _base_ambient_color := Color.WHITE
var _base_ambient_energy := 1.0
var _base_background_energy := 1.0

@onready var _sun: DirectionalLight3D = $Sun


func _ready() -> void:
	# The casino and most playable rooms use authored lighting. Rendering a
	# whole-world directional shadow map redraws thousands of surfaces each frame.
	_sun.shadow_enabled = false
	var world_env := _find_world_environment()
	if world_env:
		_environment = world_env.environment
	if _environment:
		_base_ambient_color = _environment.ambient_light_color
		_base_ambient_energy = _environment.ambient_light_energy
		_base_background_energy = _environment.background_energy_multiplier
		_install_sky_material(_environment)
	_apply(current_time_of_day())


func _process(_delta: float) -> void:
	_apply(current_time_of_day())


## Fraction of the day/night cycle elapsed right now, in [0, 1): 0.0/1.0 is midnight,
## 0.5 is noon.
func current_time_of_day() -> float:
	return compute_time_of_day(Time.get_unix_time_from_system(), DAY_LENGTH_SECONDS)


static func compute_time_of_day(unix_seconds: float, day_length_seconds: float) -> float:
	return fposmod(unix_seconds, day_length_seconds) / day_length_seconds


## Sun altitude in degrees: -90 (straight down) at midnight (t=0), 0 at the horizon
## (sunrise ~0.25, sunset ~0.75), +90 (straight overhead) at noon (t=0.5).
static func compute_sun_elevation_degrees(t: float) -> float:
	return sin(t * TAU - PI / 2.0) * 90.0


## How "daytime" the lighting should look, from 0 (full night) to 1 (full day),
## ramped smoothly across the dawn/dusk twilight band so nothing pops.
static func compute_day_factor(elevation_deg: float) -> float:
	return clampf(inverse_lerp(NIGHT_ELEVATION_DEG, DAY_ELEVATION_DEG, elevation_deg), 0.0, 1.0)


func _apply(t: float) -> void:
	var elevation := compute_sun_elevation_degrees(t)
	var factor := compute_day_factor(elevation)
	_apply_sun(elevation, factor)
	if _environment:
		_apply_environment(_environment, factor)
	if _sky_material:
		_sky_material.set_shader_parameter("blend", factor)


func _apply_sun(elevation_deg: float, factor: float) -> void:
	# At night this light becomes a soft overhead moon. A sun below the horizon
	# cannot illuminate streets or the garage at all, even with nonzero energy.
	_sun.rotation_degrees = Vector3(
		-lerpf(35.0, elevation_deg, factor),
		lerpf(SUN_AZIMUTH_DEG + 160.0, SUN_AZIMUTH_DEG, factor),
		0.0
	)
	_sun.light_energy = lerpf(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, factor)
	_sun.light_color = NIGHT_SUN_COLOR.lerp(DAY_SUN_COLOR, factor)


func _apply_environment(env: Environment, factor: float) -> void:
	env.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(_base_ambient_color, factor)
	env.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, _base_ambient_energy, factor)
	env.background_energy_multiplier = lerpf(
		NIGHT_SKY_ENERGY_MULTIPLIER, _base_background_energy, factor
	)


## Replaces the room's static day panorama with a shader that cross-fades it against
## a night panorama, so the sky itself darkens instead of just dimming the daytime
## image. Leaves the environment alone if it has no sky to swap.
func _install_sky_material(env: Environment) -> void:
	if not env.sky:
		return
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	material.set_shader_parameter("day_texture", DAY_SKY_TEXTURE)
	material.set_shader_parameter("night_texture", NIGHT_SKY_TEXTURE)
	env.sky.sky_material = material
	_sky_material = material


func _find_world_environment() -> WorldEnvironment:
	for node: Node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		return node as WorldEnvironment
	return null
