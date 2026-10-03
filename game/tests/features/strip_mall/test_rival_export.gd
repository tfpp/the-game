extends GutTest
## Export optimization repacks scene instances; source-only tests miss lost overrides.

const DECOR := preload("res://features/strip_mall/rival_decor.tscn")
const RivalModel := preload("res://features/strip_mall/rival_model.gd")


func test_repacked_restaurants_keep_sushi_identity_costume_and_placement() -> void:
	# Keep this outside the tree: export packs authored data before _ready builds avatars.
	var authored := DECOR.instantiate()
	var optimized := PackedScene.new()
	assert_eq(optimized.pack(authored), OK)
	authored.free()
	var restaurants := optimized.instantiate() as Node3D
	add_child_autofree(restaurants)
	var wok := restaurants.get_node("CityWok") as Node3D
	var sushi := restaurants.get_node("CitySushi") as Node3D
	var kim := wok.get_node("Owner") as RivalModel
	var junichi := sushi.get_node("Owner") as RivalModel
	assert_eq((wok.get_node("Sign") as Label3D).text, "CITY WOK")
	assert_eq((sushi.get_node("Sign") as Label3D).text, "CITY SUSHI")
	assert_string_contains((wok.get_node("MenuBoard") as Label3D).text, "$12")
	assert_string_contains((sushi.get_node("MenuBoard") as Label3D).text, "$15")
	assert_eq(kim.character, 0)
	assert_eq(junichi.character, 1)
	assert_eq((kim.get_node("NameTag") as Label3D).text, "Tuong Lu Kim")
	assert_eq((junichi.get_node("NameTag") as Label3D).text, "Junichi Takayama")
	assert_true(kim.torso_items.has_node("VestBack"))
	assert_true(kim.head_items.has_node("CombOver0"))
	assert_false(kim.torso_items.has_node("Sash"))
	assert_true(junichi.torso_items.has_node("Sash"))
	assert_true(junichi.torso_items.has_node("GiLapel1"))
	assert_false(junichi.torso_items.has_node("VestBack"))
	assert_false(junichi.head_items.has_node("CombOver0"))
	assert_eq(junichi.avatar.hair_style, "classic")
	assert_eq(junichi.avatar.pants_id, "pants:1")
	assert_almost_eq(kim.global_position.z, 41.0, .001)
	assert_almost_eq(junichi.global_position.z, 41.0, .001)
	var direction := (junichi.global_position - kim.global_position).normalized()
	assert_gt((-kim.global_basis.z.normalized()).dot(direction), .99)
	assert_gt((-junichi.global_basis.z.normalized()).dot(-direction), .99)
