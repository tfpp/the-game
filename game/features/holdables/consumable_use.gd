class_name ConsumableUse
extends Node
## Hand-owned, atomic consumption plus a late-joinable cosmetic animation.

const DURATION := 3.0

@export var state: Dictionary = {}
var _visual_left := 0.0
var _last_state: Dictionary = {}

@onready var hand: Hand = get_parent()
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	entity.register_action(&"consume", _may_consume, _consume)
	entity.session_reset.connect(func(_mode: Network.Mode) -> void: _finish(true))
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat != null:
		combat.player_died.connect(_died)


func active() -> bool:
	return not state.is_empty()


func view_id() -> String:
	var id := str(state.get("item", "")) if active() else hand.net_item_id
	var kind := ItemCatalog.consumable_kind(id)
	return kind if not kind.is_empty() else id


func _may_consume(peer: int, payload: Dictionary) -> bool:
	return (
		payload.is_empty()
		and peer == hand.peer_id
		and hand._player() != null
		and not active()
		and not hand.inventory().loading
		and ItemCatalog.uses_remaining(hand.net_item_id) > 0
		and _effect_allowed(hand.net_item_id)
	)


func _effect_allowed(id: String) -> bool:
	var definition := ItemCatalog.find(id)
	if definition == null:
		return false
	if definition.consumption_group.is_empty():
		return true
	var handler := get_tree().get_first_node_in_group(definition.consumption_group)
	return handler != null and bool(handler.call("can_consume", hand.peer_id, id))


func _consume(_peer: int, _payload: Dictionary) -> bool:
	var id := hand.net_item_id
	state = {"item": id, "left": DURATION}
	if id == "beer":
		var bar := get_tree().get_first_node_in_group(&"bar_companion") as BarCompanion
		if bar != null:
			bar.add_drink(hand.peer_id)
	return true


func advance(delta: float) -> void:
	if multiplayer.is_server() and active():
		var left := float(state["left"]) - delta
		if left > 0.0 and hand._player() != null:
			state = {"item": state["item"], "left": left}
		else:
			_finish(hand._player() == null)
	if state != _last_state:
		_last_state = state.duplicate()
		_visual_left = float(state.get("left", 0.0))
	else:
		_visual_left = maxf(0.0, _visual_left - delta)


func pose(player: Player, resting: Transform3D) -> Transform3D:
	if not active():
		return resting
	var elapsed := DURATION - _visual_left
	var weight := smoothstep(0.0, 0.65, elapsed) * (1.0 - smoothstep(2.4, DURATION, elapsed))
	var body := player.get_node("Body") as Node3D
	var avatar := body.get_node_or_null("Avatar") as BlockPlayerModel
	var mouth := resting
	if player.is_local() and not body.visible:
		mouth = (player.get_node("Camera") as Node3D).global_transform
		mouth.origin += mouth.basis * Vector3(0.025, -0.10, -0.18)
	elif avatar != null:
		mouth = avatar.mouth_transform()
	else:
		mouth.origin += Vector3.UP * 0.35
	var tilt := (
		Basis(Vector3.RIGHT, deg_to_rad(70.0)) if view_id() != "cigarette" else Basis.IDENTITY
	)
	var basis := mouth.basis.orthonormalized() * tilt
	var view := hand.held_view()
	if view == null:
		return resting
	var contact := view.transform * (view.get_node("Mouth") as Marker3D).position
	var target := Transform3D(basis, mouth.origin - basis * contact)
	return resting.interpolate_with(target, weight)


func _finish(discard := false) -> void:
	if multiplayer.is_server() and active():
		if hand.net_item_id == state["item"]:
			var id := hand.net_item_id
			var definition := ItemCatalog.find(id)
			if discard:
				hand.net_item_id = ""
			elif _effect_allowed(id):
				var applied := true
				if not definition.consumption_group.is_empty():
					var handler := get_tree().get_first_node_in_group(definition.consumption_group)
					applied = bool(handler.call("consume", hand.peer_id, id))
				if applied:
					hand.net_item_id = ItemCatalog.after_use(id)
		state = {}


func _died(victim: int, _attacker: int) -> void:
	if victim == hand.peer_id:
		_finish(true)


func pose_fingers(player: Player) -> void:
	if view_id() != "cigarette":
		return
	var body := player.get_node("Body") as Node3D
	var avatar := body.get_node_or_null("Avatar") as BlockPlayerModel
	var human := hand._arms.human
	if body.visible and avatar != null and avatar.body_type != &"penguin":
		human = avatar.human
	human.set_digit_curl(true, "Index", 0.35)
	human.set_digit_curl(true, "Middle", 0.45)
