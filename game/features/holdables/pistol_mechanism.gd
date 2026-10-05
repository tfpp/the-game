class_name PistolMechanism
extends Node
## Loaded rounds are a subset of existing inventory ammo, spent once by Hand.

const CAPACITY := 7
const DURATION := 1.65

@export var weapon_id := "pistol"
@export var capacity := CAPACITY
@export var reload_duration := DURATION

@export var state: Dictionary = {"loaded": 0, "left": 0.0, "initialized": false}
@onready var hand: Hand = get_parent()
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	entity.register_action(&"reload", _may_reload, _reload)
	entity.event_received.connect(_on_sound)
	entity.session_reset.connect(func(_mode: Network.Mode) -> void: _reset())
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat != null:
		combat.player_died.connect(_died)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	Controls.ensure_action(&"gun_reload", [key, pad])


func loaded() -> int:
	return mini(int(state["loaded"]), hand.inventory().ammo_for(weapon_id))


func active() -> bool:
	return float(state["left"]) > 0.0


func can_fire() -> bool:
	_prepare()
	return not active() and loaded() > 0


func record_shot() -> void:
	if multiplayer.is_server():
		_set_state(maxi(0, int(state["loaded"]) - 1), 0.0, true)


func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_prepare()
	if active():
		if ItemCatalog.base_weapon(hand.net_item_id) != weapon_id or hand._player() == null:
			_set_state(loaded(), 0.0, bool(state["initialized"]))
		else:
			var left := maxf(0.0, float(state["left"]) - delta)
			_reload_sounds(float(state["left"]), left)
			_set_state(
				mini(capacity, hand.inventory().ammo_for(weapon_id)) if left == 0.0 else loaded(),
				left,
				true
			)
	elif loaded() != int(state["loaded"]):
		_set_state(loaded(), 0.0, bool(state["initialized"]))


func _prepare() -> void:
	if (
		multiplayer.is_server()
		and not bool(state["initialized"])
		and ItemCatalog.base_weapon(hand.net_item_id) == weapon_id
		and not hand.inventory().loading
	):
		var total := hand.inventory().ammo_for(weapon_id)
		if total > 0:
			_set_state(mini(capacity, total), 0.0, true)


func _may_reload(peer: int, payload: Dictionary) -> bool:
	return (
		payload.is_empty()
		and peer == hand.peer_id
		and hand._player() != null
		and ItemCatalog.base_weapon(hand.net_item_id) == weapon_id
		and not hand.inventory().loading
		and not hand.consumption.active()
		and not active()
		and loaded() < mini(capacity, hand.inventory().ammo_for(weapon_id))
		and not FirstPersonView.firing_blocked(get_tree(), peer)
	)


func _reload(_peer: int, _payload: Dictionary) -> bool:
	_set_state(loaded(), reload_duration, true)
	return true


func _set_state(rounds: int, left: float, initialized: bool) -> void:
	state = {"loaded": rounds, "left": left, "initialized": initialized}


## Transient authority events avoid replaying old reload cues for late joiners.
func _reload_sounds(previous: float, remaining: float) -> void:
	var phases := [.18, .63, .86] if weapon_id == "pistol" else [.25, .75, .88]
	var cues: Array[StringName] = [&"reload_mag_out", &"reload_mag_in", &"reload_charge"]
	for index: int in phases.size():
		var threshold := reload_duration * (1.0 - float(phases[index]))
		if previous > threshold and remaining <= threshold:
			entity.send_event(&"reload_sound", {"cue": cues[index], "at": hand.global_position})


func _on_sound(event: StringName, payload: Dictionary) -> void:
	if event == &"reload_sound":
		GameAudio.play_at(self, StringName(payload.get("cue", "")), payload.get("at", Vector3.ZERO))


func _reset() -> void:
	if multiplayer.is_server():
		_set_state(0, 0.0, false)


func _died(victim: int, _attacker: int) -> void:
	if multiplayer.is_server() and victim == hand.peer_id:
		_set_state(loaded(), 0.0, bool(state["initialized"]))


func _unhandled_input(event: InputEvent) -> void:
	if (
		hand.peer_id == multiplayer.get_unique_id()
		and ItemCatalog.base_weapon(hand.net_item_id) == weapon_id
		and Controls.gameplay_active()
		and event.is_action_pressed(&"gun_reload")
	):
		entity.request_action(&"reload")
		get_viewport().set_input_as_handled()
