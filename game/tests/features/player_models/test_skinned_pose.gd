extends GutTest
## Pose updates should avoid idle engine work without leaving item overlays behind.

var _model: BlockPlayerModel


func before_each() -> void:
	_model = BlockPlayerModel.new()
	add_child_autofree(_model)
	_model.human.pose(_model, false, false)


func test_identical_pose_does_not_trigger_another_skeleton_update() -> void:
	var skeleton := _model.human.skeleton
	await wait_process_frames(2)
	watch_signals(skeleton)
	_model.human.pose(_model, false, false)
	_model.human.pose(_model, false, false)
	await wait_process_frames(2)
	assert_signal_not_emitted(skeleton, "pose_updated", "Unchanged bones stay clean")
	_model._head.rotation.y = 0.2
	_model.human.pose(_model, false, false)
	await wait_process_frames(2)
	assert_signal_emit_count(skeleton, "pose_updated", 1, "A changed head still updates")


func test_body_pose_restores_bones_after_an_extended_item_grip() -> void:
	var human := _model.human
	var skeleton := human.skeleton
	var original: Array[Transform3D] = []
	for bone: int in skeleton.get_bone_count():
		original.append(skeleton.get_bone_pose(bone))
	var hand := skeleton.find_bone("HandR")
	var forearm := skeleton.find_bone("ForearmR")
	var target := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
	human.reach_grip(true, target + Vector3(0, 0, -2), true)
	assert_gt(
		skeleton.get_bone_pose_position(forearm).length(),
		original[forearm].origin.length(),
		"The item grip extended the arm"
	)
	human.pose(_model, false, false)
	for bone: int in skeleton.get_bone_count():
		assert_true(
			skeleton.get_bone_pose(bone).is_equal_approx(original[bone]),
			"Restored " + skeleton.get_bone_name(bone)
		)
