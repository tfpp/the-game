extends RefCounted
## Adds the real noclip feature to a test and turns `sv_cheats` on, unlocking DevGates.

const NOCLIP := preload("res://features/noclip/feature.tscn")


static func enable(test: GutTest) -> Node:
	var noclip := NOCLIP.instantiate()
	test.add_child_autofree(noclip)
	noclip.set_physics_process(false)
	noclip.set(&"cheats_enabled", true)
	for gate: Node in test.get_tree().get_nodes_in_group(&"dev_gates"):
		(gate as DevGate).refresh()
	return noclip
