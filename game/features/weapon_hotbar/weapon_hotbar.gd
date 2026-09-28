extends Node
## Quick item switching for the local player, layered on features/inventory's
## backpack: number keys 1-8 jump straight to a slot, the mouse wheel cycles to the
## next or previous non-empty one. Both reuse `PlayerInventory.request_equip` — the
## same swap the inventory screen's Equip button sends — so the server still
## validates ownership and slot bounds; this feature only decides *which* slot to
## ask for.
##
## Also drives a fire recoil animation on every hand's held item view, listening for
## features/holdables/hand.gd's `fired` signal (broadcast to every peer alongside the
## muzzle flash), so guns visually punch back for everyone watching, not just the
## shooter.

const RECOIL_DURATION_S := 0.16
const HOTBAR_NEXT_ACTION := &"hotbar_next"
const HOTBAR_PREV_ACTION := &"hotbar_prev"

## Hand -> {view: Node3D, base: Transform3D, t: float, kick: float}
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
	for hand: Hand in _recoil.keys():
		if not seen.has(hand):
			_recoil.erase(hand)
	for hand: Hand in _connected.keys():
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
	# Mouse-wheel notches also queue a jump (Controls' classic b-hop bind); left
	# unhandled here so that still fires alongside the weapon swap.
	if event.is_action_pressed(HOTBAR_NEXT_ACTION):
		_cycle(hand, 1)
	elif event.is_action_pressed(HOTBAR_PREV_ACTION):
		_cycle(hand, -1)


## Equip whatever is in `slot`, swapping it with the currently held item — the same
## request a digit key or the inventory screen's Equip button sends.
func _equip_slot(hand: Hand, slot: int) -> void:
	hand.inventory().request_equip.rpc_id(1, slot)


## Advances a per-session cursor to the next occupied backpack slot in `direction`
## and equips it, so repeated scrolling steps through every carried item in turn.
func _cycle(hand: Hand, direction: int) -> void:
	var slot := WeaponHotbarMath.next_slot(hand.inventory().backpack, _cursor, direction)
	if slot == -1:
		return
	_cursor = slot
	_equip_slot(hand, slot)


func _on_fired(item_id: String, hand: Hand) -> void:
	var view := hand.held_view()
	if view == null:
		return
	var entry: Dictionary = _recoil.get(hand, {})
	var base: Transform3D = entry["base"] if entry.get("view") == view else view.transform
	var def := ItemCatalog.find(item_id)
	_recoil[hand] = {
		"view": view,
		"base": base,
		"t": 0.0,
		"kick": WeaponHotbarMath.kick_for_damage(def.damage if def != null else 18.0),
	}


func _update_recoil(hand: Hand, delta: float) -> void:
	if not _recoil.has(hand):
		return
	var entry: Dictionary = _recoil[hand]
	var view: Node3D = entry["view"]
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
