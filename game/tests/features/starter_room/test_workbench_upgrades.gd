extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _store: InventoryPersistence
var _record: Dictionary = {}
var _fail_save := false
var _accounts: Dictionary


func before_each() -> void:
	_accounts = Network.peer_accounts.duplicate(true)
	Network.peer_accounts[1] = {"account_id": 171}
	_store = InventoryPersistence.new()
	_store.transport = _api
	_store.set_process(false)
	add_child_autofree(_store)


func after_each() -> void:
	Network.peer_accounts = _accounts


func _api(payload: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if payload["action"] == "load":
		return {"inventory": _record}
	if _fail_save:
		return {"error": "failed"}
	_record = payload["inventory"].duplicate(true)
	return {"saved": true}


func test_recipe_consumes_exact_salvage_and_keeps_other_items_and_stash() -> void:
	var snapshot := {
		"hand": "pistol",
		"backpack": ["scrap", "scrap", "electronics", "banana", "", "", "", ""],
		"van_stash": ["scrap"]
	}
	var next := WorkbenchRecipes.candidate(snapshot, -1, "pistol")
	assert_eq(next["hand"], "tuned:pistol")
	assert_eq(next["backpack"][3], "banana")
	assert_eq(next["van_stash"], ["scrap"])
	assert_eq(snapshot["backpack"][0], "scrap", "Candidate cannot mutate live inventory")
	assert_true(WorkbenchRecipes.candidate(next, -1, "tuned:pistol").is_empty())
	assert_true(WorkbenchRecipes.candidate(snapshot, 0, "pistol").is_empty())
	assert_true(WorkbenchRecipes.candidate(snapshot, 99, "pistol").is_empty())
	snapshot["backpack"][1] = ""
	assert_true(WorkbenchRecipes.candidate(snapshot, -1, "pistol").is_empty())


func test_tuned_weapons_keep_ammo_magazine_views_and_saved_identity() -> void:
	var hand := HAND.instantiate() as Hand
	add_child_autofree(hand)
	for weapon: String in ItemCatalog.AMMO_PACKS:
		var tuned := ItemCatalog.find("tuned:" + weapon)
		var stock := ItemCatalog.find(weapon)
		assert_almost_eq(tuned.damage, stock.damage * 1.15, .0001)
		assert_eq(tuned.view_scene, stock.view_scene)
		assert_eq(tuned.fire_cooldown_s, stock.fire_cooldown_s)
		assert_eq(hand.magazine_for(tuned.id), hand.magazine_for(weapon))
		var inventory := hand.inventory()
		inventory._set_item(0, ItemCatalog.ammo_id(weapon, 3))
		assert_eq(inventory.ammo_for(tuned.id), 3)
		assert_true(inventory.spend_ammo(tuned.id))
		assert_eq(inventory.ammo_for(weapon), 2)
	assert_null(ItemCatalog.find("tuned:tuned:pistol"))
	assert_null(ItemCatalog.find("tuned:banana"))
	hand.inventory().restore(
		{"hand": "tuned:pistol", "backpack": ["tuned:shotgun"], "van_stash": ["tuned:smg"]}
	)
	assert_eq(hand.net_item_id, "tuned:pistol")
	assert_true(hand.inventory().backpack.has("tuned:shotgun"))
	assert_eq(hand.inventory().snapshot()["van_stash"], ["tuned:smg"])


func test_server_validates_range_and_stale_recipe_then_commits_before_apply() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var bench := feature.get_node("Room/Workbench") as GearWorkbench
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_store._track(hand)
	await wait_process_frames(5)
	var player := PLAYER.instantiate() as Player
	player.get_node("Sync").free()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = bench.global_position
	var inventory := hand.inventory()
	inventory._set_item(-1, "pistol")
	inventory._set_item(0, "scrap")
	inventory._set_item(1, "scrap")
	inventory._set_item(2, "electronics")
	var payload := {"slot": -1, "id": "pistol"}
	assert_true(bench._validate(1, payload))
	assert_false(bench._validate(1, {"slot": -1, "id": "pistol", "peer": 2}))
	player.net_position += Vector3.RIGHT * 6
	assert_false(bench._validate(1, payload))
	player.net_position = bench.global_position
	_fail_save = true
	bench._upgrade(1, payload)
	assert_true(inventory.loading)
	assert_eq(hand.net_item_id, "pistol")
	await wait_process_frames(10)
	assert_eq(hand.net_item_id, "pistol")
	assert_eq(inventory.backpack[0], "scrap")
	_fail_save = false
	assert_true(bench._validate(1, payload))
	bench._upgrade(1, payload)
	await wait_process_frames(10)
	assert_eq(_record["hand"], "tuned:pistol")
	assert_eq(hand.net_item_id, "tuned:pistol")
	assert_eq(inventory.backpack[0], "")
	assert_false(bench._validate(1, payload))


func test_phone_recipe_cards_and_fixed_back_remain_tappable() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var bench := feature.get_node("Room/Workbench") as GearWorkbench
	bench.items = [{"slot": -1, "id": "pistol", "available": true}]
	var screen := feature.get_node("WorkbenchScreen") as CanvasLayer
	screen.set_process(false)
	var original := get_window().size
	get_window().size = Vector2i(390, 844)
	screen.call("_resize")
	screen.call("open", bench)
	await wait_process_frames(3)
	var root := screen.get("_root") as Control
	assert_almost_eq(root.size.x, 390.0, 1.0)
	var button := (screen.get("_list") as GridContainer).get_child(0) as Button
	assert_gte(button.size.y, 106.0)
	assert_false(button.disabled)
	assert_gte((screen.get("_back") as Button).size.y, 56.0)
	screen.call("close")
	get_window().size = original
