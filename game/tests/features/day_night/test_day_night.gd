extends GutTest
## features/day_night/day_night.gd: the real-time-clock-driven sun and sky. Runs
## standalone (no WorldEnvironment in the test tree), so `_environment` and
## `_sky_material` stay null and `_apply()` only moves the sun; the environment/sky
## application methods are exercised directly, the same way
## tests/features/game_config/test_game_config.gd calls `_apply_jump_height()` on a
## config built without the full scene.

const DAY_NIGHT := preload("res://features/day_night/feature.tscn")

var _day_night: DayNight


func before_each() -> void:
	_day_night = DAY_NIGHT.instantiate() as DayNight
	add_child_autofree(_day_night)
	_day_night.set_process(false)


func test_day_length_is_48_real_minutes() -> void:
	assert_eq(DayNight.DAY_LENGTH_SECONDS, 48.0 * 60.0)


func test_time_of_day_wraps_every_day_length() -> void:
	assert_eq(DayNight.compute_time_of_day(0.0, 2880.0), 0.0)
	assert_eq(DayNight.compute_time_of_day(720.0, 2880.0), 0.25)
	assert_eq(DayNight.compute_time_of_day(1440.0, 2880.0), 0.5)
	assert_eq(DayNight.compute_time_of_day(2880.0, 2880.0), 0.0)
	assert_eq(DayNight.compute_time_of_day(2880.0 * 3.0 + 720.0, 2880.0), 0.25)


func test_time_of_day_handles_negative_input() -> void:
	assert_almost_eq(DayNight.compute_time_of_day(-720.0, 2880.0), 0.75, 0.0001)


func test_sun_elevation_at_key_times() -> void:
	assert_almost_eq(DayNight.compute_sun_elevation_degrees(0.5), 90.0, 0.001)
	assert_almost_eq(DayNight.compute_sun_elevation_degrees(0.0), -90.0, 0.001)
	assert_almost_eq(DayNight.compute_sun_elevation_degrees(1.0), -90.0, 0.001)
	assert_almost_eq(DayNight.compute_sun_elevation_degrees(0.25), 0.0, 0.001)
	assert_almost_eq(DayNight.compute_sun_elevation_degrees(0.75), 0.0, 0.001)


func test_day_factor_is_clamped_full_day_and_full_night() -> void:
	assert_eq(DayNight.compute_day_factor(90.0), 1.0)
	assert_eq(DayNight.compute_day_factor(-90.0), 0.0)
	assert_eq(DayNight.compute_day_factor(DayNight.DAY_ELEVATION_DEG), 1.0)
	assert_eq(DayNight.compute_day_factor(DayNight.NIGHT_ELEVATION_DEG), 0.0)


func test_day_factor_ramps_through_the_twilight_band() -> void:
	var mid := (DayNight.NIGHT_ELEVATION_DEG + DayNight.DAY_ELEVATION_DEG) / 2.0
	assert_almost_eq(DayNight.compute_day_factor(mid), 0.5, 0.001)


func test_apply_sun_at_noon_is_bright_and_overhead() -> void:
	_day_night._apply_sun(90.0, 1.0)
	var sun: DirectionalLight3D = _day_night.get_node("Sun")
	assert_almost_eq(sun.rotation_degrees.x, -90.0, 0.001)
	assert_eq(sun.light_energy, DayNight.DAY_SUN_ENERGY)
	assert_eq(sun.light_color, DayNight.DAY_SUN_COLOR)


func test_apply_sun_at_midnight_is_dim_moonlight() -> void:
	_day_night._apply_sun(-90.0, 0.0)
	var sun: DirectionalLight3D = _day_night.get_node("Sun")
	assert_almost_eq(sun.rotation_degrees.x, -35.0, 0.001)
	assert_almost_eq(sun.light_energy, DayNight.NIGHT_SUN_ENERGY, 0.0001)
	assert_eq(sun.light_color, DayNight.NIGHT_SUN_COLOR)
	assert_true(sun.light_energy >= 0.25)


func test_apply_environment_blends_between_night_and_captured_base() -> void:
	_day_night._base_ambient_color = Color(0.68, 0.57, 0.44)
	_day_night._base_ambient_energy = 0.65
	_day_night._base_background_energy = 1.0
	var env := Environment.new()

	_day_night._apply_environment(env, 1.0)
	assert_eq(env.ambient_light_color, _day_night._base_ambient_color)
	assert_almost_eq(env.ambient_light_energy, _day_night._base_ambient_energy, 0.0001)
	assert_almost_eq(env.background_energy_multiplier, _day_night._base_background_energy, 0.0001)

	_day_night._apply_environment(env, 0.0)
	assert_eq(env.ambient_light_color, DayNight.NIGHT_AMBIENT_COLOR)
	assert_almost_eq(env.ambient_light_energy, DayNight.NIGHT_AMBIENT_ENERGY, 0.0001)
	assert_almost_eq(env.background_energy_multiplier, DayNight.NIGHT_SKY_ENERGY_MULTIPLIER, 0.0001)
	assert_true(env.ambient_light_color.get_luminance() * env.ambient_light_energy > 0.25)


func test_runs_without_a_world_environment_in_the_tree() -> void:
	# before_each() already added _day_night to a bare test tree with no
	# WorldEnvironment; _ready() must not have crashed, and _apply() (called with
	# processing re-enabled just for this call) should only move the sun.
	_day_night._apply(0.5)
	assert_null(_day_night._environment)
	assert_null(_day_night._sky_material)
	var sun: DirectionalLight3D = _day_night.get_node("Sun")
	assert_almost_eq(sun.rotation_degrees.x, -90.0, 0.001)


func test_current_time_of_day_is_within_range() -> void:
	var t := _day_night.current_time_of_day()
	assert_true(t >= 0.0 and t < 1.0)
