extends GutTest
## Pure surface-bob math for the water feature (features/water/water_wave.gd).

const WaterWave := preload("res://features/water/water_wave.gd")


func test_surface_y_starts_at_base_when_elapsed_is_zero() -> void:
	assert_almost_eq(WaterWave.surface_y(1.0, 0.0, 0.1, 2.0), 1.0, 0.0001)


func test_surface_y_peaks_at_a_quarter_period() -> void:
	assert_almost_eq(WaterWave.surface_y(0.0, 0.5, 0.2, 2.0), 0.2, 0.0001)


func test_surface_y_troughs_at_three_quarters_period() -> void:
	assert_almost_eq(WaterWave.surface_y(0.0, 1.5, 0.2, 2.0), -0.2, 0.0001)


func test_surface_y_is_periodic() -> void:
	var a := WaterWave.surface_y(0.0, 0.3, 0.15, 2.0)
	var b := WaterWave.surface_y(0.0, 2.3, 0.15, 2.0)
	assert_almost_eq(a, b, 0.0001)
