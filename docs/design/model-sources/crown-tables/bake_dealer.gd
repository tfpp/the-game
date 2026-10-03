extends Node
## Bake full-body dealer motions to shared native bone clips; no runtime pose pass.
const OUTPUT := "res://assets/table_games/animations/dealer.res"
const LENGTHS := {
	"idle": 4.0,
	"greet": 1.8,
	"shuffle": 2.4,
	"deal": 1.2,
	"reveal": 1.4,
	"collect": 1.8,
	"payout": 1.6,
	"roll": 1.4
}


func _ready() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var model := BlockPlayerModel.new()
	model.rotation.y = PI
	model.position.y = .9144
	add_child(model)
	var library := AnimationLibrary.new()
	var skeleton := model.human.skeleton
	var path := str(model.get_path_to(skeleton))
	for motion: String in LENGTHS:
		var animation := Animation.new()
		animation.length = LENGTHS[motion]
		animation.loop_mode = Animation.LOOP_LINEAR if motion == "idle" else Animation.LOOP_NONE
		for i: int in skeleton.get_bone_count():
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath(path + ":" + skeleton.get_bone_name(i)))
		var count := ceili(animation.length * 30)
		for frame: int in range(count + 1):
			var fraction := float(frame) / count
			var wave := sin(PI * fraction)
			var left := Vector3(.19, 1.04, .40)
			var right := Vector3(-.19, 1.04, .40)
			var lean := 0.0
			var yaw := 0.0
			match motion:
				"idle":
					left.y += .012 * sin(TAU * fraction)
					right.y += .012 * sin(TAU * fraction)
					yaw = .15 * sin(TAU * fraction)
				"greet":
					right = right.lerp(Vector3(-.32, 1.48, .35), wave)
					right.x -= .04 * sin(TAU * fraction * 3) * wave
					yaw = -.16 * wave
				"shuffle":
					left = left.lerp(Vector3(.06, 1.15, .46), wave)
					right = right.lerp(Vector3(-.06, 1.15, .46), wave)
					left.y += .045 * sin(TAU * fraction * 4) * wave
					right.y -= .045 * sin(TAU * fraction * 4) * wave
				"deal":
					left = left.lerp(Vector3(.13, 1.07, .44), wave)
					right = right.lerp(Vector3(-.34, 1.01, .64), wave)
					lean = -.06 * wave
				"reveal":
					right = right.lerp(Vector3(-.10, 1.05, .61), wave)
					yaw = .12 * wave
				"collect":
					right = right.lerp(Vector3(.25 * cos(PI * fraction), 1.01, .62), wave)
					left = left.lerp(Vector3(.12, 1.05, .43), wave)
					lean = -.08 * wave
				"payout":
					left = left.lerp(Vector3(.32, 1.01, .62), wave)
					yaw = .16 * wave
					lean = -.05 * wave
				"roll":
					right = right.lerp(Vector3(-.1, 1.1 + .10 * sin(TAU * fraction * 3), .6), wave)
					lean = -.08 * wave
			model.animate(0, Vector3.ZERO, true, 1, 0, false, false, false)
			model._torso.rotation.x = lean
			model._head.rotation = Vector3(-.08 * wave, yaw, 0)
			model.human.pose(model, false, false)
			model.human.reach_grip(false, left)
			model.human.reach_grip(true, right)
			model.human.set_finger_curl(false, .28 + .30 * wave)
			model.human.set_finger_curl(true, .28 + .30 * wave)
			for i: int in skeleton.get_bone_count():
				animation.rotation_track_insert_key(
					i, fraction * animation.length, skeleton.get_bone_pose_rotation(i)
				)
		library.add_animation(StringName(motion), animation)
	assert(ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
	model.free()
	print("Baked eight full-body dealer clips: ", OUTPUT)
	get_tree().quit()
