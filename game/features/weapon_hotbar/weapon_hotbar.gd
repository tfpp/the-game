extends Node
## Quick weapon switching for the local player, layered on features/inventory's
## backpack and features/gun_machine's rig: number keys 1-8 jump straight to a
## backpack slot, 9 jumps to the gun machine's rig, and the mouse wheel cycles through
## every occupied slot in turn (backpack, then the rig). Backpack slots reuse
## `PlayerInventory.request_equip` — the same swap the inventory screen's Equip button
## sends — and the rig slot reuses `GunRig.request_equip_rig`; either way the server
## still validates ownership, so this feature only decides *which* slot to ask for.
## Equipping a weapon from one system automatically holsters the other (see
## `PlayerInventory.holster_weapon` and `GunRig.holster`), so only one weapon is ever
## held at once.
##
## Also drives a fire recoil animation on every hand's held item view, listening for
## features/holdables/hand.gd's `fired` signal (broadcast to every peer alongside the
## muzzle flash), so guns visually punch back for everyone watching, not just the
## shooter.

const RECOIL_DURATION_S := 0.16
const HOTBAR_NEXT_ACTION := &"hotbar_next"
const HOTBAR_PREV_ACTION := &"hotbar_prev"
const RIG_ACTION := &"hotbar_rig"
## The extra cycle slot for features/gun_machine's rig, one past the last backpack
## index.
const RIG_SLOT := PlayerInventory.CAPACITY

## Hand -> {view: WeakRef, base: Transform3D, t: float, kick: float}
var _recoil: Dictionary = {}
## Hands whose `fired` signal we've already connected to — `Signal.is_connected`
## can't be used for that check since the connection binds each hand as an extra
## argument, making every candidate Callable compare unequal to a fresh `.bind()`.
var _connected: Dictionary = {}
## Last backpack slot equipped by scrolling, so repeated scrolls keep advancing.
var _cursor := -1


func _ready() -> void:
	for slot: int in PlayerInventory.CAPACITY:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_1 + slot
		Controls.ensure_action(_slot_action(slot), [key])
	var rig_key := InputEventKey.new()
	rig_key.physical_keycode = KEY_9
	Controls.ensure_action(RIG_ACTION, [rig_key])
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	Controls.ensure_action(HOTBAR_NEXT_ACTION, [wheel_up])
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	Controls.ensure_action(HOTBAR_PREV_ACTION, [wheel_down])


func _process(delta: float) -> void:
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand == null:
			continue
		seen[hand] = true
		if not _connected.has(hand):
			_connected[hand] = true
			hand.fired.connect(_on_fired.bind(hand))
		_update_recoil(hand, delta)
	for hand: Variant in _recoil.keys():
		if not seen.has(hand):
			_recoil.erase(hand)
	for hand: Variant in _connected.keys():
		if not seen.has(hand):
			_connected.erase(hand)


func _unhandled_input(event: InputEvent) -> void:
	if not Controls.gameplay_active():
		return
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand == null:
		return
	for slot: int in PlayerInventory.CAPACITY:
		if event.is_action_pressed(_slot_action(slot)):
			_equip_slot(hand, slot)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(RIG_ACTION):
		_equip_rig(hand)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(HOTBAR_NEXT_ACTION):
		_cycle(hand, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(HOTBAR_PREV_ACTION):
		_cycle(hand, -1)
		get_viewport().set_input_as_handled()


## Equip whatever is in `slot`, swapping it with the currently held item — the same
## request a digit key or the inventory screen's Equip button sends.
func _equip_slot(hand: Hand, slot: int) -> void:
	var id := hand.inventory().item_at(slot)
	if id.is_empty():
		return
	var request := func() -> void:
		if is_instance_valid(hand):
			hand.inventory().request_equip.rpc_id(1, slot)
	if not ClothingCatalog.slot(id).is_empty():
		request.call()
	else:
		_request_swap(request)


## Re-equips features/gun_machine's rig for this hand's peer, if it has a holstered
## gun to bring back out. A no-op with no rig or an empty one.
func _equip_rig(hand: Hand) -> void:
	var rig := GunRig.for_peer(get_tree(), hand.peer_id)
	if rig == null or rig.net_stats.is_empty():
		return
	if rig.is_active():
		return
	var request := func() -> void:
		if is_instance_valid(rig):
			rig.request_equip_rig.rpc_id(1)
	_request_swap(request)


func _request_swap(request: Callable) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null:
		request.call()
	else:
		FirstPersonView.request_swap(player, request)


## Advances a per-session cursor to the next occupied slot in `direction` and equips
## it — a backpack slot, or `RIG_SLOT` for features/gun_machine's rig — so repeated
## scrolling steps through every weapon the player is carrying, in either system, in
## turn.
func _cycle(hand: Hand, direction: int) -> void:
	var slot := WeaponHotbarMath.next_occupied(_occupancy(hand), _cursor, direction)
	if slot == -1:
		return
	_cursor = slot
	if slot == RIG_SLOT:
		_equip_rig(hand)
	else:
		_equip_slot(hand, slot)


## One `bool` per cycle slot: whether each backpack slot holds an item, followed by
## whether features/gun_machine's rig has a gun rolled (equipped or holstered).
func _occupancy(hand: Hand) -> Array[bool]:
	var occupied: Array[bool] = []
	for id: String in hand.inventory().backpack:
		occupied.append(not id.is_empty())
	var rig := GunRig.for_peer(get_tree(), hand.peer_id)
	occupied.append(rig != null and not rig.net_stats.is_empty())
	return occupied


func _on_fired(item_id: String, hand: Hand) -> void:
	if FirstPersonView.firing_blocked(get_tree(), hand.peer_id):
		return
	var view := hand.held_view()
	if view == null:
		return
	var entry: Dictionary = _recoil.get(hand, {})
	var previous := entry.get("view") as WeakRef
	var same_view: bool = previous != null and previous.get_ref() == view
	var base: Transform3D = entry["base"] if same_view else view.transform
	var def := ItemCatalog.find(item_id)
	_recoil[hand] = {
		"view": weakref(view),
		"base": base,
		"t": 0.0,
		"kick": WeaponHotbarMath.kick_for_damage(def.damage if def != null else 18.0),
	}


func _update_recoil(hand: Hand, delta: float) -> void:
	if not _recoil.has(hand):
		return
	var entry: Dictionary = _recoil[hand]
	# Resolve to null after a swap frees the old view, before assigning a typed
	# Node3D. A raw freed reference raises an error before validity checks run.
	var reference: WeakRef = entry["view"]
	var view := reference.get_ref() as Node3D
	if not is_instance_valid(view) or view != hand.held_view():
		_recoil.erase(hand)
		return
	entry["t"] = float(entry["t"]) + delta
	var ease := WeaponHotbarMath.recoil_ease(entry["t"], RECOIL_DURATION_S)
	var base: Transform3D = entry["base"]
	if ease <= 0.0:
		view.transform = base
		_recoil.erase(hand)
		return
	view.transform = base * WeaponHotbarMath.recoil_transform(entry["kick"], ease)
	_recoil[hand] = entry


func _slot_action(slot: int) -> StringName:
	return StringName("hotbar_slot_%d" % slot)
