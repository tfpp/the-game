extends ItemPickup
## Shared key pickup using PlayerInventory. Restore it if its holder disconnects before unlocking.

@export var locked_door: NodePath
var _check_seconds := 0.0


func _ready() -> void:
	super._ready()
	_entity.session_reset.connect(_reset)


func _process(delta: float) -> void:
	super._process(delta)
	if not _entity.is_authority() or not net_taken:
		return
	_check_seconds += delta
	if _check_seconds < 0.5:
		return
	_check_seconds = 0
	var door := get_node_or_null(locked_door) as SwingDoor
	if door == null or door.net_state != SwingDoor.State.LOCKED:
		return
	for node: Node in get_tree().get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand != null and hand.inventory().has_key(item_id):
			return
	net_taken = false


func _reset(_mode: Network.Mode) -> void:
	net_taken = false
	_check_seconds = 0
