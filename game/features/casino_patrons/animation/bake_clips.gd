extends Node
## Bake the existing steady patron gait into shared native bone tracks.

const OUTPUT := "res://assets/casino_patrons/animations/locomotion.tres"
const BONES := [
	"Spine", "UpperArmL", "UpperArmR", "ForearmL", "ForearmR", "ThighL", "ThighR", "CalfL", "CalfR"
]
const SAMPLES := 48


func _ready() -> void:
	bake.call_deferred()


func bake() -> void:
	var model := PatronModel.new()
	add_child(model)
	model.build(0)
	var library := AnimationLibrary.new()
	var idle := _clip(model, false)
	library.add_animation(&"idle", idle)
	library.add_animation(&"walk", _clip(model, true))
	var reset := idle.duplicate(true) as Animation
	reset.loop_mode = Animation.LOOP_NONE
	reset.length = 0.001
	library.add_animation(&"RESET", reset)
	var result := ResourceSaver.save(library, OUTPUT)
	assert(result == OK, "Could not save patron clips")
	print("Baked patron idle/walk clips: ", OUTPUT)
	get_tree().quit()


func _clip(model: PatronModel, walking: bool) -> Animation:
	var clip := Animation.new()
	clip.loop_mode = Animation.LOOP_LINEAR
	clip.length = (
		TAU / BlockPlayerMotion.phase_step(PatronMath.WALK_SPEED, PatronModel.RIG_MAX_SPEED, 1.0)
	)
	var avatar := model.avatar
	var skeleton := avatar.human.skeleton
	var skeleton_path := str(avatar.get_path_to(skeleton))
	for bone: String in BONES:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(skeleton_path + ":" + bone))
	var torso := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(torso, NodePath("Rig/Torso"))
	var rig := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(rig, NodePath("Rig"))
	var step := clip.length / SAMPLES
	if walking:
		for frame: int in SAMPLES * 10:
			model.pose(step, 1.0, 0, 0, 0)
	else:
		model.pose(100.0, 0, 0, 0, 0)
	var count := SAMPLES if walking else 1
	for frame: int in count:
		if frame > 0:
			model.pose(step, 1.0, 0, 0, 0)
		var time := frame * step
		for track: int in BONES.size():
			clip.rotation_track_insert_key(
				track, time, skeleton.get_bone_pose_rotation(skeleton.find_bone(BONES[track]))
			)
		clip.rotation_track_insert_key(torso, time, avatar._torso.quaternion)
		clip.position_track_insert_key(rig, time, avatar._rig.position)
	if walking:
		for track: int in clip.get_track_count():
			clip.track_insert_key(track, clip.length, clip.track_get_key_value(track, 0))
	return clip
