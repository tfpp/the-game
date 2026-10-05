extends Node3D
## Cosmetic tracks consume Hand events and replicated magazine state.

@export var weapon_id := "smg"
var _hand: Node
var _reloading := false
@onready var _animation: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	process_priority = 15
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.is_in_group(&"hands"):
			_hand = ancestor
			_hand.connect(&"fired", _fired)
			break
		ancestor = ancestor.get_parent()


func _process(_delta: float) -> void:
	if _hand == null:
		return
	var mechanism: Node = _hand.call("magazine_for", weapon_id)
	var state: Dictionary = mechanism.get("state")
	if bool(mechanism.call("active")):
		if not _reloading:
			_animation.play(&"reload")
			_animation.seek(float(mechanism.get("reload_duration")) - float(state["left"]), true)
		_reloading = true
	elif _reloading:
		_animation.play(&"RESET")
		_animation.advance(0.0)
		_animation.stop()
		_reloading = false
	($SupportGrip as Node3D).transform = (
		($Pose as Node3D).transform * ($Pose/SupportGrip as Node3D).transform
	)


func _fired(id: String) -> void:
	if ItemCatalog.base_weapon(id) == weapon_id:
		_animation.play(&"fire")
