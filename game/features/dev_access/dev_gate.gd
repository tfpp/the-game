class_name DevGate
extends Node
## Hides a development entrance (its parent door plus any `extra` nodes) and blocks
## its use until the server-owned `sv_cheats` switch in features/noclip is on.
## Doors ask `DevGate.blocks(self)` in their server-side range check, so a client
## that still sees a stale door cannot travel through it.

const POLL_SEC := 0.5

## Further nodes (signs, lights) shown and hidden together with the parent.
@export var extra: Array[NodePath] = []

var _shown := true
var _poll := 0.0


static func cheats_enabled(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var noclip := tree.get_first_node_in_group(&"noclip")
	return noclip != null and bool(noclip.get(&"cheats_enabled"))


## True when `door` has a DevGate child and cheats are off.
static func blocks(door: Node) -> bool:
	for child: Node in door.get_children():
		if child is DevGate:
			return not cheats_enabled(door.get_tree())
	return false


func _ready() -> void:
	add_to_group(&"dev_gates")
	refresh()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SEC
	refresh()


## Shows or hides the entrance to match the current cheat switch.
func refresh() -> void:
	var unlocked := cheats_enabled(get_tree())
	if unlocked == _shown:
		return
	_shown = unlocked
	var targets: Array[Node] = [get_parent()]
	for path: NodePath in extra:
		var node := get_node_or_null(path)
		if node != null:
			targets.append(node)
	for node: Node in targets:
		if node is Node3D:
			(node as Node3D).visible = unlocked
		if node is CSGShape3D:
			(node as CSGShape3D).use_collision = unlocked
