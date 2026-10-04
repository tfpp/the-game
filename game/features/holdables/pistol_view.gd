extends Node3D
## Cosmetic only. Static pickups/thumbnails keep the native rest pose.

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
	var mechanism := _hand.get_node("PistolMechanism")
	var state: Dictionary = mechanism.get("state")
	if bool(mechanism.call("active")):
		if not _reloading:
			_animation.play(&"reload")
			_animation.seek(1.65 - float(state["left"]), true)
		_reloading = true
	elif _reloading:
		_animation.play(&"RESET")
		_animation.advance(0.0)
		_animation.stop()
		_reloading = false
	if not _animation.is_playing():
		($Pose/Slide as Node3D).position.z = (
			.024 if bool(state["initialized"]) and int(mechanism.call("loaded")) == 0 else 0.0
		)
	($SupportGrip as Node3D).transform = (
		($Pose as Node3D).transform * ($Pose/SupportGrip as Node3D).transform
	)


func _fired(id: String) -> void:
	if id == "pistol":
		_animation.play(&"fire")
