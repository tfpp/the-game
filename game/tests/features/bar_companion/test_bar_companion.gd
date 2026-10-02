extends GutTest

const FEATURE := preload("res://features/bar_companion/feature.tscn")
const APARTMENTS := preload("res://features/apartments/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const MACHINE := preload("res://features/slot_machine/machine.tscn")

var _bar: BarCompanion
var _home: Apartments
var _wallet: PlayerMoney
var _vivienne: Vivienne
var _bartender: Node3D


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 20000, 2: 20000}
	_home = APARTMENTS.instantiate() as Apartments
	add_child_autofree(_home)
	_bar = FEATURE.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_vivienne = _bar.get_node("Vivienne") as Vivienne
	_bartender = _bar.get_node("Bartender")


func after_each() -> void:
	Network.peer_accounts.clear()


func _player(peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = at
	player.global_position = at
	return player


func _claim_room(player: Player) -> void:
	var peer := player.get_multiplayer_authority()
	player.net_position = _home.get_node("Lobby/Desk").global_position + Vector3(0, 0, 1.5)
	assert_gt(_home.claim(peer), 0)
	player.net_position = _vivienne.global_position + Vector3(0, 0, 1)


func _talk(node: Node3D) -> NetworkedInteraction:
	return node.get_node("NetworkedEntity") as NetworkedInteraction


func test_drinks_charge_the_wallet_and_raise_then_hurt_charisma() -> void:
	_player(1, _bartender.global_position + Vector3(0, -1.1, 0.8))
	for drink: int in 3:
		assert_eq(
			_talk(_bartender)._evaluate(1, &"order", {"item": "drink"}),
			NetworkedEntity.Result.ACCEPTED
		)
		_talk(_bartender)._actions[&"order"].next_msec = 0
	assert_eq(int(_wallet.balances[1]), 20000 - 3 * CharmMath.DRINK_CENTS)
	assert_eq(int(_wallet.balances[2]), 20000, "only the buyer pays")
	assert_eq(_bar.charisma_for(1), 3)
	assert_eq(_bar.intoxication_for(1), 3)
	_talk(_bartender)._evaluate(1, &"order", {"item": "drink"})
	assert_eq(_bar.charisma_for(1), 1, "one drink too many")
	_bar.advance(CharmMath.SOBER_S * 2.0)
	_bar._publish()
	assert_eq(_bar.intoxication_for(1), 2)


func test_bartender_rejects_far_unknown_and_broke_players() -> void:
	var player := _player(1, _bartender.global_position + Vector3(0, 0, 8))
	assert_eq(
		_talk(_bartender)._evaluate(1, &"order", {"item": "drink"}), NetworkedEntity.Result.DENIED
	)
	assert_eq(_talk(_bartender)._evaluate(9, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = _bartender.global_position + Vector3(0, -1.1, 0.8)
	_wallet.balances[1] = 100
	_talk(_bartender)._evaluate(1, &"order", {"item": "drink"})
	assert_eq(int(_wallet.balances[1]), 100)
	assert_eq(_bar.intoxication_for(1), 0)


func test_win_charisma_discounts_her_price_and_fades() -> void:
	_bar.note_win(1)
	_bar.note_win(1)
	assert_eq(_bar.charisma_for(1), 4)
	assert_eq(_bar.price_for(1), CharmMath.price_cents(4))
	assert_eq(_bar.price_for(2), CharmMath.BASE_PRICE_CENTS)
	_bar.advance(CharmMath.WIN_FADE_S * 10.0)
	assert_eq(_bar.charisma_for(1), 0)
	assert_false(_bar._state.has(1), "faded players are dropped")


func test_she_needs_a_room_then_follows_the_payer() -> void:
	var player := _player(1, _vivienne.global_position + Vector3(0, 0, 1))
	assert_eq(_talk(_vivienne)._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(int(_wallet.balances[1]), 20000, "no room, no charge")
	_claim_room(player)
	_bar.note_win(1)
	assert_eq(_talk(_vivienne)._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(int(_wallet.balances[1]), 20000 - CharmMath.price_cents(2))
	assert_eq(_vivienne.net_escort, 1)
	var second := _player(2, _vivienne.global_position + Vector3(0.5, 0, 1))
	assert_false(_vivienne.can_use(second), "she's taken while escorted")
	player.net_position += Vector3(4, 0, 0)
	for step: int in 60:
		_vivienne._physics_process(1.0 / 30.0)
	var gap := _vivienne.net_position - player.net_position
	gap.y = 0.0
	assert_almost_eq(gap.length(), 0.0 + Vivienne.FOLLOW_DISTANCE, 0.05)


func test_leading_her_to_the_room_grants_a_lucky_night() -> void:
	var player := _player(1, Vector3.ZERO)
	_claim_room(player)
	_talk(_vivienne)._evaluate(1, &"use", {})
	var room := _home.floor_for(1).to_global(Apartments.unit_bounds(_home.unit_for(1)).get_center())
	room.y = _home.floor_for(1).global_position.y
	player.net_position = room
	_vivienne._physics_process(0.1)
	assert_eq(_bar.rerolls_for(1), CharmMath.LUCK_REROLLS)
	assert_eq(_bar.rerolls_for(2), 0)
	assert_eq(_bar.luck_seconds_for(1), int(CharmMath.LUCK_S))
	_vivienne._physics_process(Vivienne.LINGER_S + 0.1)
	assert_eq(_vivienne.net_escort, 0, "she goes back to her stool")
	assert_almost_eq(_vivienne.net_position.distance_to(_bar.to_global(_vivienne._seat)), 0.0, 0.01)
	_bar.advance(CharmMath.LUCK_S)
	assert_eq(_bar.rerolls_for(1), 0)


func test_disconnect_or_timeout_sends_her_back() -> void:
	var player := _player(1, Vector3.ZERO)
	_claim_room(player)
	_talk(_vivienne)._evaluate(1, &"use", {})
	_vivienne._physics_process(Vivienne.ESCORT_S + 1.0)
	assert_eq(_vivienne.net_escort, 0)
	_talk(_vivienne)._actions[&"use"].next_msec = 0
	_talk(_vivienne)._evaluate(1, &"use", {})
	assert_eq(_vivienne.net_escort, 1)
	player.free()
	_vivienne._physics_process(0.1)
	assert_eq(_vivienne.net_escort, 0)
	_bar.add_drink(1)
	_bar.forget(1)
	assert_eq(_bar.intoxication_for(1), 0)


func test_the_hallway_outside_the_room_does_not_count() -> void:
	var player := _player(1, Vector3.ZERO)
	_claim_room(player)
	var floor_node := _home.floor_for(1)
	assert_false(_home.in_unit(1, floor_node.to_global(Vector3(-12, 0.1, 0))), "corridor")
	assert_true(_home.in_unit(1, floor_node.to_global(Vector3(-12, 0.1, -5.5))), "unit 101")
	assert_false(_home.in_unit(1, floor_node.to_global(Vector3(-6, 0.1, -5.5))), "unit 102")
	assert_false(_home.in_unit(2, floor_node.to_global(Vector3(-12, 0.1, -5.5))), "no room")


func test_slot_spins_use_the_lucky_night_and_wins_add_charisma() -> void:
	var machine := MACHINE.instantiate() as SlotMachine
	add_child_autofree(machine)
	machine.set_process(false)
	machine._begin_spin(1, "Alice", [2, 2, 2], 1000)
	machine._advance(10.0)
	assert_true(machine.state["won"])
	assert_eq(_bar.charisma_for(1), int(CharmMath.WIN_CHARISMA))
	machine._begin_spin(1, "Alice", [0, 1, 2], 0)
	machine._advance(10.0)
	assert_eq(_bar.charisma_for(1), int(CharmMath.WIN_CHARISMA), "losses add nothing")
	_bar.grant_luck(1)
	assert_string_contains(machine.interaction_text(), "lucky night")


func test_stats_and_escort_are_replicated_for_late_joiners() -> void:
	var entity := _bar.get_node("NetworkedEntity") as NetworkedEntity
	assert_has(entity.replicated_properties, NodePath(".:stats"))
	assert_has(_talk(_vivienne).replicated_properties, NodePath(".:net_escort"))
	assert_has(_talk(_vivienne).continuous_properties, NodePath(".:net_position"))


func test_seated_on_the_stool_clear_of_the_counter() -> void:
	var stool := _bar.get_node("Stool/Model/Model") as MeshInstance3D
	var seat_top := (stool.global_transform * stool.get_aabb()).end.y
	var model := _vivienne.get_node("Body") as CompanionModel
	assert_eq(model.avatar.locomotion, &"seated")
	var hip := model.bone_position("ThighL").y
	assert_almost_eq(hip - seat_top, 0.07, 0.03, "sits on the seat, not above or in it")
	assert_gt(model.bone_position("FootL").y, -1.25, "feet stay above the floor")
	assert_almost_eq(seat_top, -1.25 + 0.74, 0.01)
	# The bar counter's front face is at z -9.4 (salon.tscn BarCounter).
	for bone: String in ["FootL", "FootR", "CalfL", "CalfR"]:
		assert_gt(model.bone_position(bone).z - 0.15, -9.4, bone + " stays in front of the counter")
	# Facing the bar (-Z) like the counter's other guests.
	assert_almost_eq((_vivienne.global_basis * Vector3.FORWARD).z, -1.0, 0.01)
