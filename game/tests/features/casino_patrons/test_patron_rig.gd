extends GutTest
## Casino NPCs wear the player avatar rig: clothing colors, walking and seated poses.

const PatronScene := preload("res://features/casino_patrons/patron.tscn")
const SEATED := preload("res://features/casino_patrons/stationary_seated.tscn")
const LADY := preload("res://features/casino_patrons/stationary_lady.tscn")
const GUEST := preload("res://features/casino_patrons/stationary_guest.tscn")
const SALON := preload("res://features/casino_hub/salon.tscn")


func test_every_look_uses_existing_skin_hair_and_clothing_colors() -> void:
	for look: int in PatronModel.LOOKS.size():
		var model := PatronModel.new()
		add_child_autofree(model)
		model.build(look)
		var data: Dictionary = PatronModel.LOOKS[look]
		assert_eq(model.avatar.skin_color, PlayerSkin.TONES[data["skin"]])
		assert_eq(model.avatar.shirt_color, ClothingCatalog.COLORS[data["shirt"]])
		assert_eq(model.avatar.pants_color, ClothingCatalog.COLORS[data["pants"]])
		assert_eq(model.avatar.hair_style, data["hair"])
		assert_eq(model.avatar.body_type, &"girl" if data.get("girl", false) else &"default")


func test_accessories_survive_the_rig_redecorating() -> void:
	var model := PatronModel.new()
	add_child_autofree(model)
	model.build(PatronModel.MAMDANI_LOOK)
	model.avatar.set_appearance(
		{"skin": 2, "hair": "bald", "hair_color": 1, "eyes": 1, "outfit": "casual"}
	)
	assert_not_null(model.find_child("Beard", true, false))
	assert_not_null(model.find_child("Tie", true, false))


func test_walking_patron_strides_on_the_rig() -> void:
	var model := PatronModel.new()
	add_child_autofree(model)
	model.build(0)
	var leg := model.avatar.get_node("Rig/LeftLeg") as Node3D
	var swings := []
	for i: int in 40:
		model.pose(1.0 / 30.0, 1.0, 0.0, 0.0, 0.0)
		swings.append(leg.rotation.x)
	assert_eq(model.avatar.locomotion, &"walk", "walks rather than runs at patron speed")
	assert_gt(swings.max() - swings.min(), 0.4, "the legs swing")
	for i: int in 40:
		model.pose(1.0 / 30.0, 0.0, 0.0, 0.0, 0.0)
	assert_eq(model.avatar.locomotion, &"idle")
	assert_almost_eq(leg.rotation.x, 0.0, 0.05)


func test_knocked_out_patron_sprawls() -> void:
	var model := PatronModel.new()
	add_child_autofree(model)
	model.build(1)
	model.pose(0.1, 0.0, 1.0, 0.0, 0.0)
	var arm := model.avatar.get_node("Rig/Torso/RightArm") as Node3D
	assert_gt(arm.rotation.z, 1.0, "arms flop out")
	model.pose(0.1, 0.0, 0.0, 0.0, 0.0)
	assert_eq(arm.rotation.z, 0.0, "back to normal after getting up")


func test_seated_thigh_dips_only_for_low_seats() -> void:
	assert_almost_eq(PatronModel.seated_thigh(0.9), PI / 2.0 - asin(0.45), 0.001)
	assert_almost_eq(PatronModel.seated_thigh(0.41), PI / 2.0, 0.001)
	assert_lt(PatronModel.seated_thigh(0.55), PI / 2.0)


func test_seated_guest_sits_on_the_chair_with_hands_on_the_felt() -> void:
	var guest := SEATED.instantiate() as StationaryPatron
	add_child_autofree(guest)
	var model := guest.get_node("Body") as SalonGuestModel
	assert_eq(model.avatar.locomotion, &"seated")
	assert_eq(model.avatar.body_type, &"default")
	# Chair seat tops are 0.48 m (salon_card_table.glb); thighs rest just above.
	assert_almost_eq(model.bone_position("ThighL").y, 0.55, 0.02)
	for foot: String in ["FootL", "FootR"]:
		var ankle := model.bone_position(foot).y
		assert_between(ankle, 0.05, 0.16, foot + " rests near the floor")
	# Scenes face +Z like the imported poses they replaced, towards the table.
	var knee := model.bone_position("CalfL")
	assert_gt(knee.z, model.bone_position("ThighL").z + 0.2, "knees point toward +Z")
	for right: bool in [false, true]:
		var hand := model.hand_position(right)
		assert_almost_eq(hand.y, SalonGuestModel.HAND_HEIGHT, 0.12, "hand at felt height")
		assert_gt(hand.z, 0.3, "hand reaches over the table")
	var hitbox := guest.get_node("Hitbox") as CollisionShape3D
	var size := (hitbox.shape as BoxShape3D).size
	assert_lt(size.y, 1.6, "seated hitbox is shorter than a standing one")
	assert_gt(hitbox.position.z, 0.0, "hitbox reaches forward to the knees")


func test_ladies_wear_dresses_and_guests_stand() -> void:
	var lady := LADY.instantiate() as StationaryPatron
	add_child_autofree(lady)
	var dress := lady.get_node("Body") as SalonGuestModel
	assert_eq(dress.avatar.body_type, &"girl")
	assert_eq(dress.avatar.shirt_color, dress.avatar.pants_color, "one-color dress")
	var standing := GUEST.instantiate() as StationaryPatron
	add_child_autofree(standing)
	var guest := standing.get_node("Body") as SalonGuestModel
	assert_eq(guest.avatar.locomotion, &"idle")
	assert_gt(guest.bone_position("Head").y, 1.3)


func test_guest_looks_vary_by_seat_and_stay_in_range() -> void:
	var looks := {}
	for i: int in 12:
		var dress := SalonGuestModel.guest_look(Vector3(i * 1.7, -1.5, i * 0.9), true)
		var suit := SalonGuestModel.guest_look(Vector3(i * 1.7, -1.5, i * 0.9), false)
		assert_true(PatronModel.LOOKS[dress].get("girl", false))
		assert_false(PatronModel.LOOKS[suit].get("girl", false))
		assert_gt(suit, PatronModel.INTERN_LOOK)
		looks[dress] = true
		looks[suit] = true
	assert_gt(looks.size(), 3, "guests don't all look alike")


func test_salon_uses_rig_characters_only() -> void:
	var salon := SALON.instantiate()
	add_child_autofree(salon)
	var guests := 0
	for node: Node in salon.find_children("*", "StationaryPatron", false, false):
		var body := node.get_node("Body")
		assert_true(body is SalonGuestModel or body is CardDealerModel, str(node.name))
		if body is SalonGuestModel:
			guests += 1
	assert_eq(guests, 13, "nine seated and four standing guests")


func test_guest_pose_timers_spread_updates_without_delaying_initial_pose() -> void:
	var phases: Array[float] = []
	for index: int in SalonGuestModel.POSE_PHASES:
		var guest := SEATED.instantiate() as StationaryPatron
		add_child_autofree(guest)
		var model := guest.get_node("Body") as SalonGuestModel
		phases.append(model._until_update)
		assert_eq(model._since, 0.0, "Scheduling offsets do not add animation time")
		assert_gt(model.bone_position("Head").y, 0.8, "Initial seated pose is ready")
	phases.sort()
	for index: int in phases.size():
		assert_almost_eq(
			phases[index],
			float(index + 1) * SalonGuestModel.UPDATE_S / SalonGuestModel.POSE_PHASES,
			0.00001
		)
