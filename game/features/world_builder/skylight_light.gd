extends OmniLight3D
## Broad live fill under the skylight; moonlight retains room visibility after sunset.

var _remaining := 0.0


func _ready() -> void:
	_process(0)


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0:
		return
	_remaining = 1.0
	var time := DayNight.compute_time_of_day(
		Time.get_unix_time_from_system(), DayNight.DAY_LENGTH_SECONDS
	)
	set_day_factor(DayNight.compute_day_factor(DayNight.compute_sun_elevation_degrees(time)))


func set_day_factor(factor: float) -> void:
	var daylight := clampf(factor, 0, 1)
	light_energy = lerpf(1.2, 3.0, daylight)
	light_color = Color("bbcce8").lerp(Color("fff2d9"), daylight)
