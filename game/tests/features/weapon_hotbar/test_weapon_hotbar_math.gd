extends GutTest
## Pure hotbar/recoil math (features/weapon_hotbar/weapon_hotbar_math.gd).

const WeaponHotbarMath := preload("res://features/weapon_hotbar/weapon_hotbar_math.gd")


func test_recoil_ease_starts_at_one_and_reaches_zero() -> void:
	assert_almost_eq(WeaponHotbarMath.recoil_ease(0.0, 0.2), 1.0, 0.0001)
	assert_eq(WeaponHotbarMath.recoil_ease(0.2, 0.2), 0.0)
	assert_eq(WeaponHotbarMath.recoil_ease(5.0, 0.2), 0.0)


func test_recoil_ease_decreases_over_time() -> void:
	var early := WeaponHotbarMath.recoil_ease(0.02, 0.2)
	var late := WeaponHotbarMath.recoil_ease(0.15, 0.2)
	assert_gt(early, late)


func test_recoil_ease_handles_a_zero_duration() -> void:
	assert_eq(WeaponHotbarMath.recoil_ease(0.0, 0.0), 0.0)


func test_recoil_transform_is_identity_at_zero_ease() -> void:
	var xform := WeaponHotbarMath.recoil_transform(0.1, 0.0)
	assert_true(xform.origin.is_equal_approx(Vector3.ZERO))
	assert_true(xform.basis.is_equal_approx(Basis.IDENTITY))


func test_recoil_transform_pushes_the_view_back_and_up_at_full_ease() -> void:
	var xform := WeaponHotbarMath.recoil_transform(0.1, 1.0)
	assert_almost_eq(xform.origin.z, 0.1, 0.0001)
	assert_gt(xform.origin.y, 0.0)
	assert_false(xform.basis.is_equal_approx(Basis.IDENTITY))


func test_kick_for_damage_scales_with_damage() -> void:
	var pistol := WeaponHotbarMath.kick_for_damage(25.0)
	var awp := WeaponHotbarMath.kick_for_damage(100.0)
	assert_gt(awp, pistol)


func test_kick_for_damage_clamps_to_a_sane_range() -> void:
	assert_eq(WeaponHotbarMath.kick_for_damage(0.0), 0.045)
	assert_eq(WeaponHotbarMath.kick_for_damage(1000.0), 0.15)


func test_next_slot_finds_the_nearest_occupied_slot_forward() -> void:
	var backpack := PackedStringArray(["", "", "pistol", "", "smg", "", "", ""])
	assert_eq(WeaponHotbarMath.next_slot(backpack, -1, 1), 2)
	assert_eq(WeaponHotbarMath.next_slot(backpack, 2, 1), 4)


func test_next_slot_wraps_around() -> void:
	var backpack := PackedStringArray(["pistol", "", "", "", "", "", "", ""])
	assert_eq(WeaponHotbarMath.next_slot(backpack, 0, 1), 0)


func test_next_slot_searches_backward() -> void:
	var backpack := PackedStringArray(["", "", "pistol", "", "smg", "", "", ""])
	assert_eq(WeaponHotbarMath.next_slot(backpack, 0, -1), 4)


func test_next_slot_returns_negative_one_when_the_backpack_is_empty() -> void:
	var backpack := PackedStringArray(["", "", "", "", "", "", "", ""])
	assert_eq(WeaponHotbarMath.next_slot(backpack, -1, 1), -1)


func test_next_occupied_finds_the_nearest_true_entry_forward() -> void:
	var occupied: Array[bool] = [false, false, true, false, true, false, false, false, true]
	assert_eq(WeaponHotbarMath.next_occupied(occupied, -1, 1), 2)
	assert_eq(WeaponHotbarMath.next_occupied(occupied, 2, 1), 4)
	assert_eq(WeaponHotbarMath.next_occupied(occupied, 4, 1), 8, "Wraps into the extra slot")


func test_next_occupied_wraps_around() -> void:
	var occupied: Array[bool] = [false, false, false, false, false, false, false, false, true]
	assert_eq(WeaponHotbarMath.next_occupied(occupied, 8, 1), 8)


func test_next_occupied_searches_backward() -> void:
	var occupied: Array[bool] = [false, false, true, false, false, false, false, false, true]
	assert_eq(WeaponHotbarMath.next_occupied(occupied, 0, -1), 8)


func test_next_occupied_returns_negative_one_when_nothing_is_occupied() -> void:
	var occupied: Array[bool] = [false, false, false]
	assert_eq(WeaponHotbarMath.next_occupied(occupied, -1, 1), -1)
