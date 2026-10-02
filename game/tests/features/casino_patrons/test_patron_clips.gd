extends GutTest

const Clips := preload("res://features/casino_patrons/animation/patron_locomotion.gd")


class CountingGuest:
	extends SalonGuestModel
	var updates := 0
	var elapsed := 0.0

	func _update(delta: float) -> void:
		updates += 1
		elapsed += delta
		super._update(delta)


func test_clip_walk_moves_feet_and_stopping_blends_back_to_idle() -> void:
	var model := _walker()
	var feet: Array[float] = []
	for frame: int in 120:
		model.pose(1.0 / 60.0, 1, 0, 0, 0)
		feet.append(model.bone_position("FootL").z)
	assert_gt(feet.max() - feet.min(), 0.2, "The skinned foot strides")
	assert_eq(model.avatar.locomotion, &"walk")
	for frame: int in 120:
		model.pose(1.0 / 60.0, 0, 0, 0, 0)
	assert_eq(model.avatar.locomotion, &"idle")
	assert_almost_eq(model.bone_position("FootL").z, model.bone_position("FootR").z, 0.01)
	assert_lt(absf(model.avatar._rig.position.y), 0.001, "Idle no longer bobs")


func test_head_and_knockdown_overlays_work_and_recovery_resumes_clips() -> void:
	var model := _walker()
	model.pose(0.1, 0, 0, 0, 0)
	var head := model.avatar.human.skeleton.find_bone("Head")
	var before := model.avatar.human.skeleton.get_bone_pose_rotation(head)
	model.pose(0.1, 0, 0, 0.7, 2)
	assert_ne(model.avatar.human.skeleton.get_bone_pose_rotation(head), before)
	model.pose(0.1, 0, 1, 0, 0)
	assert_false(model._clip_locomotion.tree.active, "Knockdown uses the procedural pose")
	assert_gt(model.avatar._right_arm.rotation.z, 1.0)
	model.pose(0.1, 1, 0, 0, 0)
	assert_true(model._clip_locomotion.tree.active, "Recovery resumes native playback")
	assert_eq(model.avatar.locomotion, &"walk")


func test_clips_are_shared_but_manual_playback_and_pose_are_per_character() -> void:
	var first := _walker()
	var second := _walker()
	first.pose(0.1, 1, 0, 0, 0)
	second.pose(0.1, 0, 0, 0, 0)
	var skeleton := first.avatar.human.skeleton
	var bone := skeleton.find_bone("ThighL")
	var pose := skeleton.get_bone_pose_rotation(bone)
	await wait_process_frames(2)
	assert_eq(skeleton.get_bone_pose_rotation(bone), pose, "No automatic second evaluation")
	assert_ne(first._clip_locomotion.tree, second._clip_locomotion.tree)
	var player := first.avatar.get_node("PatronClips") as AnimationPlayer
	var other := second.avatar.get_node("PatronClips") as AnimationPlayer
	assert_eq(player.get_animation_library(&""), other.get_animation_library(&""))
	assert_eq(player.get_animation_library(&""), Clips.CLIPS)
	assert_ne(first.avatar.locomotion, second.avatar.locomotion)


func test_guest_deadlines_spread_updates_and_preserve_elapsed_time() -> void:
	var guests: Array[CountingGuest] = []
	for index: int in 13:
		var guest := CountingGuest.new()
		guest.position = Vector3(index * 1.7, -1.5, index * 0.9)
		add_child_autofree(guest)
		guest.set_process(false)
		guest.updates = 0
		guest.elapsed = 0.0
		guests.append(guest)
	var peak := 0
	for frame: int in 60:
		var updated := 0
		for guest: CountingGuest in guests:
			var before := guest.updates
			guest._process(1.0 / 60.0)
			updated += guest.updates - before
		peak = maxi(peak, updated)
	assert_lt(peak, guests.size(), "Guests do not all pose on the same frame")
	for guest: CountingGuest in guests:
		assert_between(guest.updates, 9, 11, "The rate remains roughly 10 Hz")
		assert_almost_eq(guest.elapsed + guest._since, 1.0, 0.001, "No animation time is lost")


func _walker() -> PatronModel:
	var model := PatronModel.new()
	add_child_autofree(model)
	model.build(0)
	model.enable_clip_locomotion()
	return model
