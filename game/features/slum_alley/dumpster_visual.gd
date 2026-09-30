class_name DumpsterVisual
extends MeshInstance3D
## The server replicates search presence; every peer animates the same hinged lid.

const OPEN_ANGLE := -105.0
const OPEN_SECONDS := .38
const CLOSE_SECONDS := .5
@export var loot_path := NodePath("../Loot")
var _amount := 0.0
var _loot: LootContainer
@onready var _hinge: Node3D = $Hinge


func _ready() -> void:
	_loot = get_node_or_null(loot_path) as LootContainer
	# A late join shows the current pose immediately, rather than replaying an event.
	set_open_amount(1.0 if is_instance_valid(_loot) and _loot.net_active_searchers > 0 else 0.0)


func _process(delta: float) -> void:
	if not is_instance_valid(_loot):
		_loot = get_node_or_null(loot_path) as LootContainer
	var opened := is_instance_valid(_loot) and _loot.net_active_searchers > 0
	var seconds := OPEN_SECONDS if opened else CLOSE_SECONDS
	set_open_amount(move_toward(_amount, 1.0 if opened else 0.0, delta / seconds))


func set_open_amount(amount: float) -> void:
	_amount = clampf(amount, 0, 1)
	_hinge.rotation.x = deg_to_rad(OPEN_ANGLE) * smoothstep(0.0, 1.0, _amount)
