extends GutTest
## Pickup feedback (phase 1 C2): taking stash loot shows the taker a short toast
## with the item name and pawn value, alongside the existing pickup cue.

const CONTAINER := preload("res://features/loot/loot_container.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _hand: Hand


func before_each() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func after_each() -> void:
	var toast := get_tree().get_first_node_in_group(LootToast.GROUP)
	if toast != null:
		toast.free()
	await get_tree().process_frame


func _container() -> LootContainer:
	var table := LootTable.new()
	table.min_items = 2
	table.max_items = 2
	table.item_ids = PackedStringArray(["watch"])
	table.weights = PackedFloat32Array([1])
	var container := CONTAINER.instantiate() as LootContainer
	container.loot_table = table
	add_child_autofree(container)
	return container


func _toast_text() -> String:
	var toast := get_tree().get_first_node_in_group(LootToast.GROUP) as LootToast
	return toast.shown_text() if toast != null else ""


func test_message_names_item_and_value() -> void:
	assert_eq(LootToast.pickup_message("watch"), "Picked up Watch ($10)")
	assert_eq(LootToast.pickup_message("scrap"), "Picked up Scrap Metal ($1)")
	assert_eq(LootToast.pickup_message("cash_bundle"), "Picked up Cash Bundle ($5)")


func test_message_without_value_omits_price() -> void:
	assert_eq(
		LootToast.pickup_message("pistol"), "Picked up %s" % ItemCatalog.find("pistol").display_name
	)


func test_successful_take_shows_toast_and_plays_pickup() -> void:
	var cues: Array[StringName] = []
	var audio := get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if audio != null:
		audio.sound_started.connect(
			func(cue: StringName, _p: bool, _at: Vector3) -> void: cues.append(cue)
		)
	var container := _container()
	container.request_search()
	container.request_take(0, 2, "watch")
	assert_eq(_hand.inventory().backpack[2], "watch")
	assert_eq(_toast_text(), "Picked up Watch ($10)")
	if audio != null:
		assert_has(cues, &"pickup")


func test_rejected_take_shows_no_toast() -> void:
	var container := _container()
	container.request_search()
	container.request_take(0, 2, "scrap")
	container.request_take(9, 3, "watch")
	assert_eq(_toast_text(), "")


func test_toast_fades_out_and_reuses_one_node() -> void:
	var first := LootToast.show_text(get_tree(), "a")
	var second := LootToast.show_text(get_tree(), "b")
	assert_same(first, second)
	assert_eq(second.shown_text(), "b")
	second._process(LootToast.DURATION_S + 0.1)
	assert_eq(second.shown_text(), "")
