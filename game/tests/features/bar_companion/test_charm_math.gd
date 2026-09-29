extends GutTest

const HUD := preload("res://features/bar_companion/charm_hud.gd")


func test_first_drinks_charm_then_too_many_hurt() -> void:
	assert_eq(CharmMath.charisma(0.0, 0.0), 0)
	assert_eq(CharmMath.charisma(0.0, 1.0), 1)
	assert_eq(CharmMath.charisma(0.0, 3.0), 3)
	assert_eq(CharmMath.charisma(0.0, 4.0), 1, "the fourth drink costs two points")
	assert_eq(CharmMath.charisma(0.0, 5.0), 0, "never below zero")
	assert_eq(CharmMath.charisma(6.0, 5.0), 5, "being drunk eats into win charisma too")
	assert_eq(CharmMath.charisma(6.0, 3.0), 9)
	assert_eq(CharmMath.charisma(6.0, 3.0 + 0.5), 8)
	assert_eq(CharmMath.charisma(100.0, 3.0), CharmMath.MAX_CHARISMA)


func test_price_falls_with_charisma_to_a_floor() -> void:
	assert_eq(CharmMath.price_cents(0), 5000)
	assert_eq(CharmMath.price_cents(1), 4650)
	assert_eq(CharmMath.price_cents(5), 3250)
	assert_eq(CharmMath.price_cents(10), 1500)
	for points: int in range(1, CharmMath.MAX_CHARISMA + 1):
		assert_true(CharmMath.price_cents(points) <= CharmMath.price_cents(points - 1))


func test_decay_and_mood() -> void:
	assert_almost_eq(CharmMath.decay(2.0, 45.0, 90.0), 1.5, 0.0001)
	assert_eq(CharmMath.decay(0.2, 90.0, 90.0), 0.0)
	assert_eq(CharmMath.mood(0.0), "sober")
	assert_eq(CharmMath.mood(2.0), "tipsy")
	assert_eq(CharmMath.mood(4.0), "too drunk")


func test_hud_text() -> void:
	assert_eq(HUD.status_text(0, 0, 0, false), "")
	assert_eq(HUD.status_text(3, 2, 0, false), "Charisma 3 (tipsy)")
	assert_eq(HUD.status_text(0, 0, 125, true), "Lucky night 2:05 · Lead Vivienne to your room")
