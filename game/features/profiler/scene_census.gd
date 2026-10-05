class_name SceneCensus
extends RefCounted
## Counts the render and per-frame costs that matter most on the single-threaded
## WebGL2 client: dynamic lights, shadowed lights, processing nodes and meshes.


## Census of `root` and its descendants. Hidden lights are not counted as active.
static func count(root: Node) -> Dictionary:
	var result := {
		"lights": 0,
		"shadowed_lights": 0,
		"omni": 0,
		"spot": 0,
		"directional": 0,
		"process": 0,
		"physics_process": 0,
		"meshes": 0,
	}
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for node: Node in nodes:
		if node.is_processing():
			result["process"] += 1
		if node.is_physics_processing():
			result["physics_process"] += 1
		if node is MeshInstance3D or node is GridMap or node is MultiMeshInstance3D:
			result["meshes"] += 1
		var light := node as Light3D
		if light == null or not light.is_visible_in_tree():
			continue
		result["lights"] += 1
		if light.shadow_enabled:
			result["shadowed_lights"] += 1
		if light is OmniLight3D:
			result["omni"] += 1
		elif light is SpotLight3D:
			result["spot"] += 1
		else:
			result["directional"] += 1
	return result


## Lights whose range reaches `point`: an estimate of per-pixel light work there.
static func lights_reaching(root: Node, point: Vector3) -> int:
	var total := 0
	for node: Node in root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not light.is_visible_in_tree():
			continue
		if light is DirectionalLight3D:
			total += 1
			continue
		var reach: float = (
			light.get("omni_range") if light is OmniLight3D else light.get("spot_range")
		)
		if light.global_position.distance_to(point) <= reach:
			total += 1
	return total
