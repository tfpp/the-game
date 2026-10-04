extends RefCounted
## Native tracks stay editable in Godot; all positions are relative to rest pivots.


static func library() -> AnimationLibrary:
	var result := AnimationLibrary.new()
	var fire := Animation.new()
	fire.length = 0.16
	_track(
		fire,
		"Pose/Slide:position",
		[0.0, 0.025, 0.06, 0.14],
		[Vector3.ZERO, Vector3(0, 0, .024), Vector3(0, 0, .024), Vector3.ZERO]
	)
	_track(
		fire,
		"Pose/Barrel:rotation",
		[0.0, 0.035, 0.07, 0.14],
		[Vector3.ZERO, Vector3(.045, 0, 0), Vector3(.045, 0, 0), Vector3.ZERO]
	)
	_track(
		fire,
		"Pose/Hammer:rotation",
		[0.0, 0.018, 0.075, 0.14],
		[Vector3.ZERO, Vector3(-.45, 0, 0), Vector3.ZERO, Vector3.ZERO]
	)
	result.add_animation(&"fire", fire)
	var reload := Animation.new()
	reload.length = 1.65
	_track(
		reload,
		"Pose:rotation",
		[0.0, .2, .95, 1.45, 1.65],
		[
			Vector3.ZERO,
			Vector3(.12, 0, -.40),
			Vector3(.12, 0, -.40),
			Vector3(.04, 0, -.08),
			Vector3.ZERO
		]
	)
	_track(
		reload,
		"Pose:position",
		[0.0, .2, 1.3, 1.65],
		[Vector3.ZERO, Vector3(-.12, .17, -.06), Vector3(-.12, .17, -.06), Vector3.ZERO]
	)
	_track(
		reload,
		"Pose/Magazine:position",
		[0.0, .18, .48, .74, .98, 1.25, 1.65],
		[
			Vector3.ZERO,
			Vector3.ZERO,
			Vector3(-.03, -.08, .01),
			Vector3(-.06, -.10, .01),
			Vector3(-.03, -.08, .01),
			Vector3.ZERO,
			Vector3.ZERO
		]
	)
	_track(
		reload,
		"Pose/Slide:position",
		[0.0, .1, 1.3, 1.43, 1.54, 1.65],
		[
			Vector3(0, 0, .024),
			Vector3(0, 0, .024),
			Vector3(0, 0, .024),
			Vector3(0, 0, .030),
			Vector3.ZERO,
			Vector3.ZERO
		]
	)
	_track(
		reload,
		"Pose/SupportGrip:position",
		[0.0, .18, .48, .74, .98, 1.25, 1.5, 1.65],
		[
			Vector3(-.007, -.035, .018),
			Vector3(-.02, -.075, .02),
			Vector3(.003, -.105, .028),
			Vector3(-.027, -.125, .028),
			Vector3(.003, -.105, .028),
			Vector3(-.02, -.06, .01),
			Vector3(-.04, .06, .03),
			Vector3(-.007, -.035, .018)
		]
	)
	result.add_animation(&"reload", reload)
	var idle_hand := Quaternion(Vector3.BACK, .2)
	var magazine_hand := magazine_hand_rotation()
	_rotation_track(
		reload,
		[0.0, .18, .35, .98, 1.25, 1.43, 1.54, 1.65],
		[
			idle_hand,
			idle_hand,
			magazine_hand,
			magazine_hand,
			idle_hand,
			magazine_hand,
			magazine_hand,
			idle_hand
		]
	)
	var inspect := Animation.new()
	inspect.length = 2.0
	_track(
		inspect,
		"Pose:rotation",
		[0.0, .35, 1.35, 2.0],
		[Vector3.ZERO, Vector3(.1, -.5, -.35), Vector3(.1, -.5, -.35), Vector3.ZERO]
	)
	result.add_animation(&"inspect", inspect)
	var reset := Animation.new()
	reset.length = .01
	for path: String in [
		"Pose:position",
		"Pose:rotation",
		"Pose/Slide:position",
		"Pose/Barrel:rotation",
		"Pose/Hammer:rotation",
		"Pose/Magazine:position"
	]:
		_track(reset, path, [0.0], [Vector3.ZERO])
	_track(reset, "Pose/SupportGrip:position", [0.0], [Vector3(-.007, -.035, .018)])
	_rotation_track(reset, [0.0], [idle_hand])
	result.add_animation(&"RESET", reset)
	return result


static func magazine_hand_rotation() -> Quaternion:
	# Turn the palm-up support pose into a left-side grasp around a magazine.
	var support := Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN)
	var magazine := Basis(Vector3.DOWN, Vector3.BACK, Vector3.LEFT)
	return (magazine * support.inverse()).get_rotation_quaternion()


static func _rotation_track(
	animation: Animation, times: Array[float], values: Array[Quaternion]
) -> void:
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Pose/SupportGrip"))
	for index: int in times.size():
		animation.track_insert_key(track, times[index], values[index])


static func _track(
	animation: Animation, path: String, times: Array[float], values: Array[Vector3]
) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for index: int in times.size():
		animation.track_insert_key(track, times[index], values[index])
