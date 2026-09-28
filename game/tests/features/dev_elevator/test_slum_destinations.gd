extends GutTest
## SlumDestinations.pick() (features/dev_elevator/slum_destinations.gd) reads the
## `slum_arrival_points` group directly, so it doesn't care how deep the Marker3D sits
## or which feature owns it — just that the node was tagged with
## slum_arrival_point.gd.

const SlumArrivalPoint := preload("res://features/dev_elevator/slum_arrival_point.gd")
const SlumDestinations := preload("res://features/dev_elevator/slum_destinations.gd")


func test_returns_null_when_nothing_is_registered() -> void:
	assert_null(SlumDestinations.pick(get_tree()))


func test_returns_the_only_registered_point() -> void:
	var point := SlumArrivalPoint.new()
	point.slum_name = "Parking Garage"
	add_child_autofree(point)
	assert_eq(SlumDestinations.pick(get_tree()), point)


func test_always_returns_one_of_several_registered_points() -> void:
	var points: Array[SlumArrivalPoint] = []
	for i in 3:
		var point := SlumArrivalPoint.new()
		add_child_autofree(point)
		points.append(point)
	for i in 10:
		assert_true(points.has(SlumDestinations.pick(get_tree())))
