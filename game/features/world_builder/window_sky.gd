extends Node
## Opaque window backdrops follow the same clock as the world sky.

const MATERIAL := preload("res://features/world_builder/window_sky.tres")
var _remaining := 0.0


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0:
		return
	_remaining = 1.0
	var time := DayNight.compute_time_of_day(
		Time.get_unix_time_from_system(), DayNight.DAY_LENGTH_SECONDS
	)
	var elevation := DayNight.compute_sun_elevation_degrees(time)
	MATERIAL.set_shader_parameter("day_factor", DayNight.compute_day_factor(elevation))
