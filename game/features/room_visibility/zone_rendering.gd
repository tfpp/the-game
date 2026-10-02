extends Node
## Presentation only: static visuals are classified once; moving/new visuals at 10 Hz.
## Reserve layers 19/20 for the two garages, without hiding nodes or changing physics.

const ZONE_MASK := (1 << 18) | (1 << 19)
const UPDATE_SECONDS := 0.1

var _visuals: Dictionary[int, Dictionary] = {}
var _moving_visuals: Dictionary[int, Dictionary] = {}
var _registered: Dictionary[int, bool] = {}
var _camera: Camera3D
var _original_mask := 0
var _elapsed := 0.0


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	get_tree().node_added.connect(_node_added)
	# All feature scenes finish building before the first rendering frame.
	_scan.call_deferred()


func _scan() -> void:
	for node: Node in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		_register(node, false)


func _node_added(node: Node) -> void:
	if node is VisualInstance3D:
		_register_added.call_deferred(weakref(node))


func _register(node: Node, added: bool) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var visual := node as VisualInstance3D
	var id := visual.get_instance_id()
	if _registered.has(id):
		return
	_registered[id] = true
	var zone: RenderZone
	var shared := false
	var moving := added
	var ancestor: Node = visual
	while ancestor != null:
		if ancestor.is_in_group(&"render_zone_shared"):
			shared = true
		if ancestor is PhysicsBody3D and not ancestor is StaticBody3D:
			moving = true
		if ancestor is RenderZone:
			zone = ancestor as RenderZone
			break
		ancestor = ancestor.get_parent()
	var entry := {
		"node": visual,
		"id": id,
		"light_mask": (visual as Light3D).light_cull_mask if visual is Light3D else 0,
		"original": visual.layers,
		"zone": zone,
		"shared": shared,
		"moving": moving and zone == null
	}
	_visuals[id] = entry
	if entry["moving"]:
		_moving_visuals[id] = entry
	visual.tree_exiting.connect(_unregister.bind(id))
	_apply(entry)


func _apply(entry: Dictionary) -> void:
	var visual := entry["node"] as VisualInstance3D
	var zone := entry["zone"] as RenderZone
	var mask: int = entry["original"]
	if is_instance_valid(zone):
		mask = zone.render_mask()
		if entry["shared"]:
			mask |= int(entry["original"])
	elif entry["moving"]:
		for candidate: Node in get_tree().get_nodes_in_group(&"render_zones"):
			var region := candidate as RenderZone
			if region.contains(visual.global_position):
				mask = region.render_mask()
				break
	visual.layers = mask
	# Prevent garage lights illuminating other zones and vice versa.
	if visual is Light3D:
		var lighting_mask := mask & ZONE_MASK
		if mask & ~ZONE_MASK:
			lighting_mask |= int(entry["light_mask"]) & ~ZONE_MASK
		(visual as Light3D).light_cull_mask = lighting_mask


func _process(delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())
	_elapsed += delta
	if _elapsed < UPDATE_SECONDS:
		return
	_elapsed = 0.0
	refresh_moving()


func refresh_moving() -> void:
	for id: int in _moving_visuals.keys():
		var entry := _moving_visuals[id]
		if not is_instance_valid(entry["node"]) or not entry["node"].is_inside_tree():
			_unregister(id)
		else:
			_apply(entry)


func _unregister(id: int) -> void:
	if not _visuals.has(id):
		return
	var entry := _visuals[id]
	var visual := entry["node"] as VisualInstance3D
	if is_instance_valid(visual):
		visual.layers = entry["original"]
		if visual is Light3D:
			(visual as Light3D).light_cull_mask = entry["light_mask"]
		var callback := _unregister.bind(id)
		if visual.tree_exiting.is_connected(callback):
			visual.tree_exiting.disconnect(callback)
	_visuals.erase(id)
	_moving_visuals.erase(id)
	_registered.erase(id)


func update_camera(camera: Camera3D) -> void:
	if camera != _camera:
		_restore_camera()
		_camera = camera
		if camera != null:
			_original_mask = camera.cull_mask
	if camera == null:
		return
	camera.cull_mask = _original_mask & ~ZONE_MASK
	for node: Node in get_tree().get_nodes_in_group(&"render_zones"):
		var zone := node as RenderZone
		if zone.contains(camera.global_position):
			camera.cull_mask = zone.render_mask()
			break


func _restore_camera() -> void:
	if is_instance_valid(_camera):
		_camera.cull_mask = _original_mask
	_camera = null


func _exit_tree() -> void:
	_restore_camera()
	for id: int in _visuals.keys():
		_unregister(id)


func _register_added(reference: WeakRef) -> void:
	# Socket attachment frees cap visuals synchronously during procedural builds.
	# Resolve a weak reference after the build instead of passing a freed typed Node.
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_register(node, true)
