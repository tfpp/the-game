extends GutTest

const FEATURE := preload("res://features/player_models/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const SCREEN := preload("res://features/inventory/inventory_screen.gd")

var _models: PlayerModels
var _saved_character := ""


func before_each() -> void:
	_saved_character = SettingsStore.load_text("character")
	_models = FEATURE.instantiate() as PlayerModels
	add_child_autofree(_models)
	_models.set_process(false)
	_models.get_node("ModelPicker").set_process(false)


func after_each() -> void:
	await get_tree().process_frame
	SettingsStore.save_text("character", _saved_character)


func test_legacy_looks_keep_the_original_chest_and_optional_fields_are_independent() -> void:
	var legacy := {"skin": 2, "hair": "long", "hair_color": 1, "eyes": 2}
	for extra: Dictionary in [{}, {"outfit": "tactical"}, {"chest": "full"}]:
		var look := legacy.merged(extra)
		assert_true(PlayerAppearance.valid(look))
		var avatar := BlockPlayerModel.new()
		avatar.set_appearance(look)
		add_child_autofree(avatar)
		assert_eq(avatar.chest, str(extra.get("chest", "default")))
		assert_eq(avatar.outfit, str(extra.get("outfit", "casual")))
	assert_eq(PlayerAppearance.defaults()["chest"], "default")


func test_server_rejects_invalid_chests_and_forged_identity_without_changing_state() -> void:
	var look := _full_look()
	assert_eq(_models.entity._evaluate(7, &"appearance", look), NetworkedEntity.Result.ACCEPTED)
	for value: Variant in ["unknown", "", 1, 0.5, true, null, {}, ["full"]]:
		var bad := look.duplicate()
		bad["chest"] = value
		assert_eq(_models.entity._evaluate(7, &"appearance", bad), NetworkedEntity.Result.DENIED)
		assert_eq(_models.appearance_for(7), look)
	var forged := look.duplicate()
	forged["peer_id"] = 1
	assert_eq(_models.entity._evaluate(7, &"appearance", forged), NetworkedEntity.Result.DENIED)
	# Also reject unknown fields in a five-field legacy document.
	forged = {"skin": 0, "hair": "classic", "hair_color": 0, "eyes": 0, "peer_id": 1}
	assert_false(PlayerAppearance.valid(forged))
	assert_eq(_models.appearance_for(1)["chest"], "default")


func test_peers_have_independent_choices_and_cannot_mutate_the_server_snapshot() -> void:
	var look := _full_look()
	_models.entity._evaluate(7, &"appearance", look)
	_models.entity._evaluate(9, &"appearance", PlayerAppearance.defaults())
	look["chest"] = "default"
	var copy := _models.appearance_for(7)
	copy["chest"] = "default"
	assert_eq(_models.appearance_for(7)["chest"], "full")
	assert_eq(_models.appearance_for(9)["chest"], "default")
	assert_eq(_models.appearance_for(1)["chest"], "default")


func test_offline_picker_request_saves_and_reconnect_restores_the_accepted_choice() -> void:
	var player := _player(1)
	var picker := _models.get_node("ModelPicker")
	picker._select(1, "chest", PlayerAppearance.CHESTS)
	assert_eq(_models.appearance_for(1)["chest"], "full")
	assert_eq(SettingsStore.load_data("character")["chest"], "full")
	picker._select(2, "hair", PlayerAppearance.HAIR_STYLES)
	assert_eq(SettingsStore.load_data("character")["chest"], "full")
	assert_eq(SettingsStore.load_data("character")["hair"], "swept")
	_models._reset_session(Network.Mode.OFFLINE)
	picker._on_mode_changed(Network.Mode.OFFLINE)
	picker._process(0)
	assert_eq(_models.appearance_for(1)["chest"], "full")
	assert_eq(_models.appearance_for(1)["hair"], "swept")
	assert_true(is_instance_valid(player))
	var fresh := FEATURE.instantiate() as PlayerModels
	add_child_autofree(fresh)
	assert_eq(fresh.get_node("ModelPicker")._saved["chest"], "full")


func test_late_spawn_and_respawn_apply_the_existing_authoritative_snapshot() -> void:
	_models.entity._evaluate(7, &"appearance", _full_look())
	var sync := _models.entity.get_node("Sync") as MultiplayerSynchronizer
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:appearances")))
	var player := _player(7)
	_models._process(0)
	var original := player.get_node("Body/Avatar") as BlockPlayerModel
	assert_eq(original.chest, "full")
	assert_eq(original.human.shape_weight(PlayerChest.SHAPE), 1.0)
	player.free()
	var respawn := _player(7)
	_models._process(0)
	var replacement := respawn.get_node("Body/Avatar") as BlockPlayerModel
	assert_eq(replacement.chest, "full")
	assert_eq(replacement.human.shape_weight(PlayerChest.SHAPE), 1.0)
	_models._remove_peer(7)
	assert_eq(_models.appearance_for(7)["chest"], "default")
	_models.entity._evaluate(1, &"appearance", _full_look())
	_models._reset_session(Network.Mode.OFFLINE)
	assert_true(_models.appearances.is_empty())


func test_picker_preview_tracks_the_option_without_changing_other_axes() -> void:
	var picker := _models.get_node("ModelPicker")
	var page: Control = picker.settings_page_build()
	add_child_autofree(page)
	_models.entity._evaluate(1, &"head", {"value": "frog"})
	_models.entity._evaluate(1, &"tail", {"value": "fluffy"})
	picker._select(1, "chest", PlayerAppearance.CHESTS)
	picker._refresh()
	var choice := picker._choices["chest"] as OptionButton
	assert_eq(choice.item_count, 2)
	assert_eq(choice.selected, 1)
	assert_eq(choice.custom_minimum_size.y, 38.0, "Same tap target as other settings")
	assert_eq(choice.focus_mode, Control.FOCUS_ALL, "Existing controller navigation works")
	assert_eq(picker._preview.model.chest, "full")
	assert_eq(picker._preview.model.head_type, &"frog")
	assert_eq(picker._preview.model.tail_type, &"fluffy")


func test_inventory_preview_reuses_the_same_appearance_and_keeps_equipment_unchanged() -> void:
	_player(1)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	var inventory := hand.inventory()
	inventory.collect("shirt:4")
	inventory.collect("pants:3")
	inventory.collect("shotgun")
	var before := inventory.snapshot()
	_models.entity.request_action(&"appearance", _full_look())
	var screen := SCREEN.new()
	add_child_autofree(screen)
	screen.esc_menu_open()
	assert_eq(screen._preview.model.chest, "full")
	assert_eq(screen._preview.model.human.shape_weight(PlayerChest.SHAPE), 1.0)
	assert_eq(screen._preview.model.shirt_id, "shirt:4")
	assert_eq(inventory.snapshot(), before, "Cosmetics do not equip or spend inventory items")
	screen._close(false)


func test_chest_does_not_change_capsule_eyes_height_movement_or_first_person_arms() -> void:
	var player := _player(1)
	_models._process(0)
	var avatar := player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	var collider := player.get_node("Collider") as CollisionShape3D
	var shape := collider.shape
	var eye := player.get_node("Camera") as Camera3D
	var eyes := eye.position
	var movement := player.movement
	var factor := _models.height_scale_for(1)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	hand.net_item_id = "shotgun"
	add_child_autofree(hand)
	hand.set_process(false)
	_models.entity.request_action(&"appearance", _full_look())
	_models._process(0)
	avatar._process(0)
	hand._process(0)
	assert_eq(collider.shape, shape)
	assert_eq(eye.position, eyes)
	assert_eq(player.movement, movement)
	assert_eq(_models.height_scale_for(1), factor)
	assert_eq(player.get_multiplayer_authority(), 1)
	assert_false(avatar.is_visible_in_tree(), "The chest remains hidden in first person")
	assert_true(hand._arms.visible)
	assert_true(bool(hand._arms.human.material.get_shader_parameter("arms_only")))
	assert_eq(hand._arms.human.shape_weight(PlayerChest.SHAPE), 0.0)
	(player.get_node("Body") as Node3D).show()
	avatar._process(0.1)
	hand._process(0)
	assert_true(avatar.is_visible_in_tree())
	assert_false(hand._arms.visible, "Third person keeps the existing connected avatar arms")


func _full_look() -> Dictionary:
	var look := PlayerAppearance.defaults()
	look["chest"] = "full"
	return look


func _player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_process(false)
	player.set_physics_process(false)
	return player
