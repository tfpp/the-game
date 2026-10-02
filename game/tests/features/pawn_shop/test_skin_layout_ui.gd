extends GutTest

const SHOP := preload("res://features/pawn_shop/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _shop: Node3D
var _skins: PrawnSkins


func before_each() -> void:
	_shop = SHOP.instantiate() as Node3D
	add_child_autofree(_shop)
	_skins = _shop.get_node("PrawnSkins") as PrawnSkins
	_skins.set_process(false)
	(_shop.get_node("Room") as StreamedRoom).load_room(60000)
	await wait_physics_frames(4)


func test_crate_has_floor_clear_approach_and_wall_mounted_sign() -> void:
	assert_eq(_skins.global_position, Vector3(-4, 0, -3978.9))
	var customer := _shop.to_global(Vector3(-4, .95, 22.4))
	var space := _shop.get_world_3d().direct_space_state
	var floor_hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(customer, customer + Vector3.DOWN * 2)
	)
	assert_false(floor_hit.is_empty())
	assert_almost_eq(floor_hit["position"].y, _skins.global_position.y, .001)
	var shape := CapsuleShape3D.new()
	shape.radius = .4064
	shape.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var route: Array[Vector3] = [
		_shop.to_global(Vector3(-3.5, .95, 27)),
		_shop.to_global(Vector3(-8, .95, 26.5)),
		_shop.to_global(Vector3(-8, .95, 22.4)),
		customer,
	]
	for index: int in route.size() - 1:
		query.transform.origin = route[index]
		query.motion = route[index + 1] - route[index]
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Arrival to crate is clear")
	query.transform.origin = customer
	query.motion = Vector3.ZERO
	assert_true(space.intersect_shape(query).is_empty(), "Room to stand and use it")
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = customer
	assert_true(_skins.can_use(player))
	var sign := _skins.get_node("Sign") as SignBoard
	var wall_hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			sign.global_position + Vector3.BACK, sign.global_position + Vector3.FORWARD * 2
		)
	)
	assert_false(wall_hit.is_empty())
	assert_almost_eq(sign.global_position.z, wall_hit["position"].z, .01, "Flush on wall")
	assert_eq(sign.mount, SignBoard.Mount.FLUSH)
	assert_true(_skins.is_in_group(&"interactables"))
	assert_true(_skins.entity.in_range(player))
	assert_false(_skins.entity.target().is_ancestor_of(_shop.get_node("Room")))


func test_collection_panel_empty_odds_preview_exchange_and_modal_cleanup() -> void:
	var before := Controls.playing
	var menu := _skins.menu
	var data := {
		"revision": 0,
		"document": PrawnSkinCatalog.empty_document(),
		"odds": [6000, 2500, 1000, 400, 100],
		"refunds": [50, 100, 200, 500, 1000],
		"configured": true,
		"message": "",
	}
	menu.receive(&"show", data)
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	menu._navigate("collection", "")
	assert_string_contains(_labels(menu._rows), "No skins yet")
	menu._navigate("contents", "harbour")
	for text: String in ["60.00%", "25.00%", "10.00%", "4.00%", "1.00%"]:
		assert_string_contains(_labels(menu._rows), text)
	var buy := _button(menu._rows, "Buy sealed")
	assert_true(buy.disabled, "No nearby local player: cannot buy")
	data["document"]["skins"]["brine"] = 1
	menu.receive(&"update", data)
	menu._navigate("skin", "brine")
	assert_true(_button(menu._rows, "Exchange ONE").disabled)
	data["document"]["skins"]["brine"] = 2
	menu.receive(&"update", data)
	assert_false(_button(menu._rows, "Exchange ONE").disabled)
	assert_string_contains(_labels(menu._rows), "Pistol")
	var icon := menu._rows.get_child(0) as PrawnSkinIcon
	assert_eq(icon.skin, "brine")
	menu.close()
	assert_false(menu.is_in_group(&"modal_ui"))
	assert_false(menu._panel.visible)
	Controls.playing = before
	await wait_process_frames(2)


func test_reveal_centres_committed_winner_and_closing_stops_it() -> void:
	var before := Controls.playing
	var menu := _skins.menu
	var document := PrawnSkinCatalog.empty_document()
	document["skins"]["crown"] = 1
	(
		menu
		. receive(
			&"show",
			{
				"revision": 1,
				"document": document,
				"odds": PrawnSkinCatalog.DEFAULT_ODDS,
				"refunds": [50, 100, 200, 500, 1000],
				"reward": "crown",
				"configured": true,
			}
		)
	)
	assert_true(menu._revealing)
	assert_eq(menu._reveal._strip.get_child(12).get_child(0).skin, "crown")
	for card: VBoxContainer in menu._reveal._strip.get_children():
		assert_true(card.get_child(0).skin in PrawnSkinCatalog.CRATES["harbour"]["skins"])
	await wait_seconds(2.5)
	assert_false(menu._revealing)
	assert_almost_eq(
		menu._reveal._strip.position.x + 116.0 * 12.5,
		menu._reveal.size.x * .5,
		1.0,
		"Saved winner settles under the centre pointer"
	)
	assert_eq(menu._selected, "crown")
	assert_string_contains(menu._data["message"], "new skin")
	menu.close()
	(
		menu
		. receive(
			&"show",
			{
				"revision": 2,
				"document": document,
				"reward": "crown",
				"configured": true,
			}
		)
	)
	menu.close()
	await wait_seconds(2.5)
	assert_false(menu._panel.visible)
	assert_false(menu.is_in_group(&"modal_ui"))
	Controls.playing = before


func _labels(root: Node) -> String:
	var result := ""
	for label: Label in root.find_children("*", "Label", true, false):
		result += label.text + "\n"
	return result


func _button(root: Node, prefix: String) -> Button:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.text.begins_with(prefix):
			return button
	return null
