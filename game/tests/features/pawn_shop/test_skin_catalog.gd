extends GutTest

const CATALOG := preload("res://features/pawn_shop/skin_catalog.gd")


func test_configured_odds_are_exact_and_boundaries_choose_the_right_tier() -> void:
	assert_true(CATALOG.valid_odds(CATALOG.DEFAULT_ODDS))
	for bad: Array in [
		[6000, 2500, 1000, 400, 99], [-1, 10001, 0, 0, 0], [10000], [10001, 0, 0, 0, 0]
	]:
		var typed: Array[int] = []
		typed.assign(bad)
		assert_false(CATALOG.valid_odds(typed))
	for crate: String in CATALOG.CRATES:
		var counts: Array[int] = [0, 0, 0, 0, 0]
		for ticket: int in 10000:
			var skin := CATALOG.roll(crate, CATALOG.DEFAULT_ODDS, ticket)
			counts[CATALOG.SKINS[skin][2]] += 1
		assert_eq(counts, CATALOG.DEFAULT_ODDS)
	assert_eq(CATALOG.roll("harbour", [0, 0, 0, 0, 10000], 0), "crown")
	assert_eq(CATALOG.roll("harbour", CATALOG.DEFAULT_ODDS, 10000), "")
	assert_eq(CATALOG.roll("unknown", CATALOG.DEFAULT_ODDS, 0), "")


func test_buy_open_duplicate_exchange_and_equipment_are_pure_mutations() -> void:
	var original := CATALOG.empty_document()
	var bought := _change(original, "buy", "harbour")
	assert_eq(bought["delta"], -500)
	assert_eq(bought["document"]["crates"]["harbour"], 1)
	assert_eq(original, CATALOG.empty_document(), "Input is unchanged")
	var opened := _change(bought["document"], "open", "harbour")
	assert_eq(opened["delta"], 0)
	assert_eq(opened["reward"], "brine")
	assert_eq(opened["document"]["crates"]["harbour"], 0)
	assert_eq(opened["document"]["skins"]["brine"], 1)
	assert_true(_change(opened["document"], "exchange", "brine").is_empty())
	var equipped := _change(opened["document"], "equip", "brine")
	assert_eq(equipped["document"]["equipped"], {"pistol": "brine"})
	equipped["document"]["skins"]["brine"] = 2
	var sold := _change(equipped["document"], "exchange", "brine")
	assert_eq(sold["delta"], 50)
	assert_eq(sold["document"]["skins"]["brine"], 1)
	assert_eq(sold["document"]["equipped"], {"pistol": "brine"})
	var unequipped := _change(sold["document"], "unequip", "pistol")
	assert_true(unequipped["document"]["equipped"].is_empty())


func test_empty_invalid_overflow_and_unowned_actions_do_nothing() -> void:
	for action: String in ["open", "equip", "exchange", "invent"]:
		assert_true(_change(CATALOG.empty_document(), action, "brine").is_empty())
	assert_true(_change(CATALOG.empty_document(), "buy", "bad").is_empty())
	assert_true(_change(CATALOG.empty_document(), "unequip", "rocket").is_empty())
	var full := CATALOG.empty_document()
	full["crates"]["harbour"] = 999999
	assert_true(_change(full, "buy", "harbour").is_empty())
	full["skins"]["brine"] = 999999
	assert_true(_change(full, "open", "harbour").is_empty())
	full["skins"]["brine"] = 2
	assert_true(CATALOG.change(full, "exchange", "brine", CATALOG.DEFAULT_ODDS, [-1]).is_empty())


func test_saved_document_filters_unknown_and_incompatible_equipment() -> void:
	var document := {
		"crates": {"harbour": 3.0, "bad": 1},
		"skins": {"brine": 2.0, "net": -1},
		"equipped": {"smg": "brine", "pistol": "brine", "awp": "king"},
	}
	assert_eq(
		CATALOG.clean(document),
		{
			"crates": {"harbour": 3},
			"skins": {"brine": 2},
			"equipped": {"pistol": "brine"},
		}
	)
	assert_eq(CATALOG.clean({"crates": [], "skins": "bad"}), CATALOG.empty_document())


func test_every_preview_uses_an_existing_compatible_weapon_without_changing_stats() -> void:
	for id: String in CATALOG.SKINS:
		var data: Array = CATALOG.SKINS[id]
		var weapon := ItemCatalog.find(data[1])
		assert_not_null(weapon)
		var before := [
			weapon.damage,
			weapon.fire_cooldown_s,
			weapon.pellet_count,
			weapon.spread_degrees,
			weapon.id,
			weapon.view_scene
		]
		var view: Array = CATALOG.SKINS[id]
		assert_eq(view[1], weapon.id)
		var painted := PrawnSkinAppearance.create_view(id)
		assert_not_null(painted.get_node_or_null("Muzzle"))
		assert_not_null(painted.get_node_or_null("Grip"))
		assert_eq(
			[
				weapon.damage,
				weapon.fire_cooldown_s,
				weapon.pellet_count,
				weapon.spread_degrees,
				weapon.id,
				weapon.view_scene
			],
			before
		)
		var mesh := painted.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var shader := mesh.material_override
		assert_true(shader is ShaderMaterial)
		PrawnSkinAppearance.apply(painted, "")
		assert_false(mesh.material_override is ShaderMaterial)
		var plain := ItemCatalog.create_view(weapon.id)
		var plain_mesh := plain.find_children("*", "MeshInstance3D", true, false)[0]
		assert_eq(mesh.material_override, plain_mesh.material_override)
		painted.free()
		plain.free()


func _change(document: Dictionary, action: String, id: String) -> Dictionary:
	return CATALOG.change(document, action, id, CATALOG.DEFAULT_ODDS, [50, 100, 200, 500, 1000])
