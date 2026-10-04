extends GutTest
## The hat equipment slot: the top hat is clothing that fills its own slot, can be
## stowed and dropped, and sits on top of every head the avatar can wear.

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _hand: Hand
var _inventory: PlayerInventory


func before_each() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_inventory = _hand.inventory()


func after_each() -> void:
	await get_tree().process_frame


func test_catalog_knows_the_top_hat() -> void:
	assert_eq(ClothingCatalog.slot(ClothingCatalog.TOP_HAT), "hat")
	assert_eq(ClothingCatalog.title(ClothingCatalog.TOP_HAT), "Top hat")
	assert_eq(ClothingCatalog.slot("hat:99"), "")
	var def := ItemCatalog.find(ClothingCatalog.TOP_HAT)
	assert_eq(def.category, ItemDefinition.Category.CLOTHING)
	assert_eq(def.display_name, "Top hat")


func test_collecting_wears_the_hat_then_fills_the_backpack() -> void:
	assert_true(_inventory.collect(ClothingCatalog.TOP_HAT))
	assert_eq(_inventory.hat, ClothingCatalog.TOP_HAT)
	assert_eq(_inventory.item_at(-4), ClothingCatalog.TOP_HAT)
	assert_eq(_hand.net_item_id, "", "A hat never lands in the hand")
	assert_true(_inventory.collect("hat:7"))
	assert_eq(_inventory.backpack[0], "hat:7")
	_inventory.request_equip(0)
	assert_eq(_inventory.hat, "hat:7")
	assert_eq(_inventory.backpack[0], ClothingCatalog.TOP_HAT)


func test_stow_and_drop_the_hat() -> void:
	_inventory.collect(ClothingCatalog.TOP_HAT)
	_inventory.request_stow(-4)
	assert_eq(_inventory.hat, "")
	assert_eq(_inventory.backpack[0], ClothingCatalog.TOP_HAT)
	_inventory.request_equip(0)
	assert_eq(_inventory.hat, ClothingCatalog.TOP_HAT)
	_inventory.request_drop(-5)
	assert_eq(_inventory.hat, ClothingCatalog.TOP_HAT, "Out-of-range slot is ignored")


func test_hat_replicates_to_late_joiners() -> void:
	var config := (_hand.get_node("Sync") as MultiplayerSynchronizer).replication_config
	assert_true(config.has_property(NodePath("Inventory:hat")))
	assert_true(config.property_get_spawn(NodePath("Inventory:hat")))


func test_avatar_wears_the_hat_on_every_head() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	model.set_process(false)
	model.set_hat(ClothingCatalog.TOP_HAT)
	var hat := model.find_child("Hat", true, false) as TopHat
	assert_not_null(hat)
	assert_true(hat.get_parent() is BoneAttachment3D, "Human heads carry it on the head bone")
	await wait_physics_frames(2)
	# The human crown (hair included) tops out at y 0.84 in the rest pose.
	assert_almost_eq(hat.global_position.y, 0.81, 0.04)
	for head: String in ["frog", "bird"]:
		model.set_head_type(head)
		hat = model.find_child("Hat", true, false) as TopHat
		assert_eq(hat.get_parent().name, "Head", "%s head wears the hat" % head)
		assert_eq(model.find_children("Hat", "", true, false).size(), 1)
	model.set_head_type("human")
	model.set_body_type("penguin")
	hat = model.find_child("Hat", true, false) as TopHat
	assert_eq(hat.get_parent().name, "Head", "The penguin costume wears it too")
	model.set_hat("")
	assert_null(model.find_child("Hat", true, false))
	model.set_hat("shirt:2")
	assert_eq(model.hat_id, "", "Only hat items go on the head")
