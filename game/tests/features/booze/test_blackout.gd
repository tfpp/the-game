extends GutTest
## Server-owned blackouts: the eighth drink collapses a player, strips them to their
## underwear, sobers them up and wakes them on a metro platform (real MetroService).

const BOOZE := preload("res://features/booze/feature.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const METRO := preload("res://features/metro/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _booze: Booze
var _bar: BarCompanion
var _hand: Hand
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	_player.position = Vector3(-4, 1.0, -8)
	_player.net_position = _player.position
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)
	_bar = BAR.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_booze = BOOZE.instantiate() as Booze
	add_child_autofree(_booze)
	_booze.set_process(false)
	_booze.get_node("DrunkView").set_process(false)
	_booze.get_node("DrunkView").set_physics_process(false)
	_booze._bar()
	var inventory := _hand.inventory()
	inventory.shirt = _first("shirt")
	inventory.pants = _first("pants")
	inventory.hat = _first("hat")


func after_each() -> void:
	await get_tree().process_frame


func _first(slot: String) -> String:
	return slot + ":3"


func _drink(count: int) -> void:
	for _i: int in count:
		_bar.add_drink(1)


func _metro() -> MetroService:
	var metro := METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	return metro


func test_seven_drinks_stay_up_and_the_eighth_collapses_the_drinker() -> void:
	_hand.net_item_id = "pistol"
	_drink(7)
	_booze.advance(0.1)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.NONE, "seven drinks: hammered, standing")
	_drink(1)
	assert_true(_booze._pending.has(1))
	assert_false(_booze.can_consume(1, "martini"), "no more drinks once it is coming")
	_booze.advance(0.1)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.COLLAPSE)
	assert_eq(_hand.net_item_id, "", "whatever was in hand goes into the bag")
	assert_true(_hand.inventory().backpack.has("pistol"))
	assert_false(_hand.inventory().shirt.is_empty(), "still dressed while falling")
	_booze.advance(BoozeRules.COLLAPSE_S)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.OUT)
	assert_eq(_hand.inventory().shirt, "")
	assert_eq(_hand.inventory().pants, "")
	assert_eq(_hand.inventory().hat, "")
	for id: String in [_first("shirt"), _first("pants"), _first("hat")]:
		assert_true(_hand.inventory().backpack.has(id), "%s packed, not lost" % id)
	assert_eq(_bar.intoxication_for(1), 0, "slept it off")
	# Without a metro the drinker wakes where they fell.
	_booze.advance(BoozeRules.OUT_S)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.WAKE)
	_booze.advance(BoozeRules.WAKE_S)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.NONE)
	assert_true(_booze.blackouts.is_empty())
	assert_true(_booze.can_consume(1, "martini"), "can drink again afterwards")


func test_blackout_wakes_the_drinker_on_a_loaded_metro_platform() -> void:
	var metro := _metro()
	await wait_physics_frames(3)
	_drink(8)
	_booze.advance(0.1)
	_booze.advance(BoozeRules.COLLAPSE_S)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.OUT)
	assert_true(metro.transfers.pending.has(1))
	assert_eq(metro.transfers.pending[1]["kind"], "wake")
	var target: Vector3 = _booze._deliveries[1]["position"]
	var station := -1
	for index: int in 4:
		if metro.stations[index].contains(target):
			station = index
	assert_ne(station, -1, "drop-off is inside a metro station")
	_booze.advance(BoozeRules.OUT_S + 1.0)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.OUT, "stays out until the platform loads")
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"], "client reported the platform floor")
	assert_true(metro.stations[station].is_loaded())
	metro.transfers._physics_process(0.1)
	assert_false(metro.transfers.pending.has(1))
	assert_lt(_player.net_position.distance_to(target), 0.002, "teleported onto the platform")
	assert_true(is_equal_approx(absf(_player.yaw), 0.0) or is_equal_approx(absf(_player.yaw), PI))
	assert_false(_booze._deliveries.has(1))
	_booze.advance(0.6)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.WAKE, "wakes shortly after arriving")
	_booze.advance(BoozeRules.WAKE_S)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.NONE)
	assert_lt(_player.net_position.distance_to(target), 0.002)


func test_unreachable_metro_gives_up_and_wakes_in_place() -> void:
	var metro := _metro()
	await wait_physics_frames(3)
	_drink(8)
	_booze.advance(0.1)
	_booze.advance(BoozeRules.COLLAPSE_S)
	assert_true(metro.transfers.pending.has(1))
	_booze.advance(BoozeRules.DELIVERY_TIMEOUT_S + 0.1)
	assert_false(metro.transfers.pending.has(1), "abandoned drop-off is cancelled")
	_booze.advance(0.1)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.WAKE)


func test_full_backpack_keeps_overflow_clothes_where_the_drinker_fell() -> void:
	var holdables := preload("res://features/holdables/feature.tscn").instantiate()
	add_child_autofree(holdables)
	for slot: int in PlayerInventory.CAPACITY - 1:
		_hand.inventory().backpack[slot] = "scrap"
	var moved := _hand.inventory().stow_equipment([-1, -2, -3, -4])
	assert_eq(moved.size(), 3)
	assert_eq(_hand.inventory().backpack[PlayerInventory.CAPACITY - 1], _first("shirt"))
	var thrown := holdables.get_node("Thrown")
	assert_eq(thrown.get_child_count(), 2, "pants and hat dropped as shared pickups")
	for item: Node in thrown.get_children():
		assert_lt((item as ThrownItem).from.distance_to(_player.net_position), 2.0)
	assert_eq(_hand.inventory().pants, "")
	assert_eq(_hand.inventory().stow_equipment([-2]), [] as Array[String], "already undressed")


func test_collapse_waits_for_an_active_sip_and_clears_on_death_or_disconnect() -> void:
	_hand.net_item_id = "whiskey"
	_drink(7)
	_hand.request_primary_action()
	assert_true(_hand.consumption.active())
	_hand._process(ConsumableUse.DURATION + 0.1)
	assert_eq(_hand.net_item_id, "whiskey:2", "the sip finished normally")
	assert_true(_booze._pending.has(1))
	_booze.advance(0.0)
	assert_eq(_booze.phase_for(1), BoozeRules.Phase.COLLAPSE)
	assert_true(_hand.inventory().backpack.has("whiskey:2"), "rest of the bottle kept")
	var combat := Combat.new()
	add_child_autofree(combat)
	_booze._connect()
	combat.player_died.emit(1, 1)
	assert_true(_booze.blackouts.is_empty(), "death ends the blackout")
	_booze._set_phase(2, BoozeRules.Phase.OUT)
	_booze._timers[2] = 1.0
	_booze._forget(2)
	assert_true(_booze.blackouts.is_empty(), "disconnect clears")
	_booze._set_phase(1, BoozeRules.Phase.WAKE)
	_booze._reset(Network.Mode.OFFLINE)
	assert_true(_booze.blackouts.is_empty(), "session reset clears")


func test_every_peer_lays_the_body_down_and_stands_it_back_up() -> void:
	var body := _player.get_node("Body") as Node3D
	_booze._set_phase(1, BoozeRules.Phase.COLLAPSE)
	for _frame: int in 40:
		_booze.present(0.05)
	assert_eq(_booze.lying_weight(1), 1.0)
	var hull := _player.movement.hull_height_m()
	var expected := BoozeRules.lying_body(_player.yaw, hull, BoozeRules.STANDARD_HEIGHT, 1.0)
	assert_true(body.transform.is_equal_approx(expected))
	# A late joiner sees the same lying body from the replicated phase snapshot.
	var late := Booze.new()
	late.blackouts = _booze.blackouts.duplicate()
	assert_eq(late.phase_for(1), BoozeRules.Phase.COLLAPSE)
	late.free()
	_booze._set_phase(1, BoozeRules.Phase.WAKE)
	_booze.present(0.1)
	assert_eq(_booze.lying_weight(1), 1.0, "still lying while coming to")
	for _frame: int in 160:
		_booze.present(0.05)
	assert_eq(_booze.lying_weight(1), 0.0)
	assert_true(body.position.is_zero_approx())
	assert_almost_eq(body.rotation.x, 0.0, 0.0001)
	_booze._clear(1)
	_booze.present(0.1)
	assert_true(body.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, _player.yaw))))
