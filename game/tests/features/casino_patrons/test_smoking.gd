extends GutTest

const SEATED := preload("res://features/casino_patrons/stationary_seated.tscn")
const LADY := preload("res://features/casino_patrons/stationary_lady.tscn")
const GUEST := preload("res://features/casino_patrons/stationary_guest.tscn")
const FURNISHINGS := preload("res://features/casino_hub/gridmap/furnishings.tscn")

var _npc: StationaryPatron
var _model: SalonGuestModel


func before_each() -> void:
	_npc = _guest(GUEST)
	_model = _npc._body as SalonGuestModel


func _guest(scene: PackedScene) -> StationaryPatron:
	var npc := scene.instantiate() as StationaryPatron
	var model := npc.get_node("Body") as SalonGuestModel
	model.smoking = true
	add_child_autofree(npc)
	npc.set_physics_process(false)
	model.set_process(false)
	return npc


func _pose(time: float) -> void:
	_model._time = time
	_model._update(0.04)


func test_draw_and_exhale_have_separate_smooth_phases() -> void:
	assert_eq(PatronSmoking.draw_weight(0.0), 0.0)
	assert_eq(PatronSmoking.draw_weight(2.0), 1.0)
	assert_eq(PatronSmoking.draw_weight(4.0), 0.0)
	assert_between(PatronSmoking.draw_weight(1.0), 0.1, 0.9)
	assert_eq(PatronSmoking.draw_weight(12.0), PatronSmoking.draw_weight(2.0))
	assert_false(PatronSmoking.is_exhaling(2.0), "draw before breathing out")
	assert_true(PatronSmoking.is_exhaling(3.8))
	assert_false(PatronSmoking.is_exhaling(5.0))


func test_cigarette_contacts_animated_mouth_and_hand_in_rotated_world_space() -> void:
	_npc.position = Vector3(7, -1.25, -5)
	_npc.rotation.y = 1.7
	_pose(2.0)
	var smoke := _model._smoking
	var mouth := smoke.cigarette.get_node("Mouth") as Marker3D
	var grip := smoke.cigarette.get_node("Grip") as Marker3D
	assert_lt(mouth.global_position.distance_to(_model.avatar.mouth_transform().origin), 0.001)
	assert_lt(grip.global_position.distance_to(_model.hand_position(true)), 0.025)
	assert_gt(
		smoke.cigarette.to_global(Vector3(0, 0, -0.025)).distance_to(mouth.global_position),
		0.07,
		"lit tip points away from the face"
	)
	assert_false(smoke.exhale.emitting)
	_pose(3.8)
	assert_true(smoke.exhale.emitting)
	assert_lt(
		smoke.exhale.global_position.distance_to(_model.avatar.mouth_transform().origin), 0.001
	)


func test_seated_suit_and_dress_smokers_keep_feet_and_left_hand_at_table() -> void:
	for scene: PackedScene in [SEATED, LADY]:
		var npc := _guest(scene)
		var model := npc._body as SalonGuestModel
		model._time = 2.0
		model._update(0.04)
		assert_eq(model.avatar.locomotion, &"seated")
		assert_almost_eq(model.bone_position("ThighL").y, SalonGuestModel.CHAIR_HIP, 0.02)
		assert_almost_eq(model.hand_position(false).y, SalonGuestModel.HAND_HEIGHT, 0.12)
		var grip := model._smoking.cigarette.get_node("Grip") as Marker3D
		assert_lt(model.hand_position(true).distance_to(grip.global_position), 0.025)


func test_smoke_rises_expands_fades_and_does_not_follow_a_moving_hand() -> void:
	var smoke := _model._smoking
	assert_eq(smoke.exhale.amount + smoke.tip_smoke.amount, 28)
	for particles: CPUParticles3D in [smoke.exhale, smoke.tip_smoke]:
		assert_false(particles.local_coords)
		assert_gt(particles.gravity.y, 0.0)
		assert_gt(
			particles.scale_amount_curve.sample(1.0), particles.scale_amount_curve.sample(0.0)
		)
		assert_eq(particles.color_ramp.get_color(0).a, 0.0)
		assert_eq(particles.color_ramp.get_color(particles.color_ramp.get_point_count() - 1).a, 0.0)
		assert_eq(particles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_lte(particles.lifetime, 2.8)


func test_lowering_moves_the_cigarette_away_from_the_mouth() -> void:
	_pose(2.0)
	var drawn := _model._smoking.cigarette.global_position
	_pose(5.0)
	assert_gt(drawn.distance_to(_model._smoking.cigarette.global_position), 0.2)
	assert_true(_model._smoking.tip_smoke.emitting, "resting cigarette still smoulders")
	assert_false(_model._smoking.exhale.emitting)


func test_death_culls_all_smoke_and_respawn_can_resume_without_old_cloud() -> void:
	_pose(3.8)
	_npc.take_hit(1)
	_model._process(0.1)
	assert_false(_model._smoking.visible)
	assert_false(_model._smoking.exhale.emitting)
	assert_false(_model._smoking.tip_smoke.emitting)
	_npc._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	_pose(5.0)
	assert_true(_model._smoking.visible)
	assert_true(_model._smoking.tip_smoke.emitting)
	assert_false(_model._smoking.exhale.emitting)


func test_distant_or_headless_guests_stop_particles_and_nearby_guests_resume() -> void:
	_model._process(0.1)
	assert_false(_model._smoking.visible, "no camera: no presentation cost")
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	camera.position = Vector3(100, 0, 0)
	_model._process(0.1)
	assert_false(_model._smoking.tip_smoke.emitting)
	camera.position = Vector3(0, 1.5, 2)
	_model._process(0.1)
	assert_true(_model._smoking.tip_smoke.emitting)


func test_live_casino_has_three_smokers_without_moving_guests_or_changing_hitboxes() -> void:
	var furnishings := FURNISHINGS.instantiate() as Node3D
	add_child_autofree(furnishings)
	var smokers: Array[String] = []
	for node: Node in furnishings.get_children():
		if not node is StationaryPatron:
			continue
		var npc := node as StationaryPatron
		var model := npc._body as SalonGuestModel
		if model != null and model.smoking:
			smokers.append(str(npc.name))
			assert_true(model._smoking != null)
			var expected := model.transform * model.hitbox_bounds()
			assert_almost_eq(npc._collider.position, expected.get_center(), Vector3.ONE * 0.001)
			assert_eq((npc._collider.shape as BoxShape3D).size, expected.size)
	assert_eq(smokers, ["Patron0_2", "Patron2_1", "GuestAtBar"])
	assert_eq(furnishings.get_node("GuestAtBar").position, Vector3(-8.2, -1.25, -8.25))
	assert_eq(furnishings.get_node("Patron0_2").position, Vector3(-7.161701, -1.25, -5.103984))
	assert_eq(furnishings.get_node("Patron2_1").position, Vector3(-5.5, -1.25, 4.95))


func test_late_dead_smoker_snapshot_stays_silent_and_other_guests_have_no_cigarettes() -> void:
	var late := GUEST.instantiate() as StationaryPatron
	(late.get_node("Body") as SalonGuestModel).smoking = true
	late.net_alive = false
	add_child_autofree(late)
	var model := late._body as SalonGuestModel
	model._process(0.1)
	assert_false(model._smoking.visible)
	assert_false(model._smoking.exhale.emitting)
	assert_false(model._smoking.tip_smoke.emitting)
	var normal := GUEST.instantiate() as StationaryPatron
	add_child_autofree(normal)
	assert_null((normal._body as SalonGuestModel)._smoking, "default pose stays unchanged")
