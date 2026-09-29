extends Node
## Attack from the touch FIRE button and the controller's right trigger.
##
## Both press the same actions the left mouse button does: `primary_action` (punch or
## use the held item) and `gun_fire` (shoot the gun rig). The right trigger is an
## analog axis, so it is turned into one press when it crosses `TRIGGER_PRESS` and one
## release when it falls back below `TRIGGER_RELEASE`, instead of binding the axis
## directly and firing on every tiny motion event. Every request still goes through the
## owning feature's server RPCs.

const ATTACK_ACTIONS: Array[StringName] = [&"primary_action", &"gun_fire"]
const TRIGGER_PRESS := 0.5
const TRIGGER_RELEASE := 0.3

var trigger_held := false


func _ready() -> void:
	Controls.input_reset.connect(_on_input_reset)


func _input(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion:
		return
	var motion := event as InputEventJoypadMotion
	if motion.axis != JOY_AXIS_TRIGGER_RIGHT:
		return
	var next := trigger_state(trigger_held, motion.axis_value)
	if next == trigger_held:
		return
	if next and not Controls.gameplay_active():
		return
	trigger_held = next
	send_attack(next)


func _on_input_reset() -> void:
	if trigger_held:
		trigger_held = false
		send_attack(false)


## Hysteresis for the analog trigger: whether it counts as held after reading `value`.
static func trigger_state(held: bool, value: float) -> bool:
	return value > TRIGGER_RELEASE if held else value >= TRIGGER_PRESS


## Press or release every attack action as if the left mouse button changed.
static func send_attack(pressed: bool) -> void:
	for action: StringName in ATTACK_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
