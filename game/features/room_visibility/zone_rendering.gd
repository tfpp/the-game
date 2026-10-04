extends Node
## Presentation only: static visuals are classified once; moving/new visuals at 10 Hz.
## Reserve layers 19/20 for the two garages, without hiding nodes or changing physics.

const ZONE_MASK := (1 << 18) | (1 << 19)
const UPDATE_SECONDS := 0.1

var _visuals: Dictionary[int, Dictionary] = {}
var _moving_visuals: Dictionary[int, Dictionary] = {}
var _registered: Dictionary[int, bool] = {}
var _gridmaps: Dictionary[int, Dictionary] = {}
var _camera: Camera3D
var _original_mask := 0
var _elapsed := 0.0
var _handheld_light_mask := -1


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
	for node: Node in get_tree().root.find_children("*", "GridMap", true, false):
		_register(node, false)


func _node_added(node: Node) -> void:
	if node is VisualInstance3D or node is GridMap:
		_register_added.call_deferred(weakref(node))


func _register(node: Node, added: bool) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is GridMap:
		_register_gridmap(node as GridMap)
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
		if ancestor is ZoneScope:
			zone = ancestor.get_node_or_null("Map") as RenderZone
			if zone != null:
				break
		ancestor = ancestor.get_parent()
	var entry := {
		"node": visual,
		"id": id,
		"light_mask": (visual as Light3D).light_cull_mask if visual is Light3D else 0,
		"original": visual.get_meta(FirstPersonView.LAYERS_META, visual.layers),
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
	if visual.get_meta(FirstPersonView.ACTIVE_META, false):
		visual.layers = FirstPersonView.MASK
		return
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
		visual.layers |= FirstPersonView.MASK
		var lighting_mask := mask & ZONE_MASK
		if mask & ~ZONE_MASK:
			lighting_mask |= int(entry["light_mask"]) & ~ZONE_MASK
		lighting_mask &= ~FirstPersonView.MASK
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.cull_mask & mask & ~FirstPersonView.MASK:
			lighting_mask |= FirstPersonView.MASK
		(visual as Light3D).light_cull_mask = lighting_mask


func _process(delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())
	var mask := _camera.cull_mask & ~FirstPersonView.MASK if _camera != null else 0
	if mask != _handheld_light_mask:
		_handheld_light_mask = mask
		for entry: Dictionary in _visuals.values():
			if is_instance_valid(entry["node"]) and entry["node"] is Light3D:
				_apply(entry)
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
	if _gridmaps.has(id):
		var grid := _gridmaps[id]["node"] as GridMap
		if is_instance_valid(grid):
			for instance: RID in _gridmaps[id]["instances"]:
				RenderingServer.instance_set_layer_mask(instance, 1)
			var callback := _unregister.bind(id)
			if grid.tree_exiting.is_connected(callback):
				grid.tree_exiting.disconnect(callback)
		_gridmaps.erase(id)
		_registered.erase(id)
		return
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
	# Membership remains authoritative when noclip takes the camera outside bounds.
	for scope: Node in get_tree().get_nodes_in_group(&"zone_scopes"):
		if scope.multiplayer != camera.multiplayer:
			continue
		if camera.multiplayer.get_unique_id() not in (scope as ZoneScope).members:
			continue
		var map := scope.get_node_or_null("Map") as RenderZone
		if map != null:
			camera.cull_mask = map.render_mask()
			return
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
	for id: int in _gridmaps.keys():
		_unregister(id)
	for id: int in _visuals.keys():
		_unregister(id)


## GridMap is not a VisualInstance3D and exposes no visual layer property. Its
## native baked mesh instances expose rendering RIDs; collision and saved cells
## remain owned by GridMap. Static streamed maps need this only once per load.
func _register_gridmap(grid: GridMap) -> void:
	var id := grid.get_instance_id()
	if _registered.has(id) or grid.mesh_library == null:
		return
	var zone: RenderZone
	var ancestor := grid.get_parent()
	while ancestor != null:
		if ancestor is RenderZone:
			zone = ancestor as RenderZone
			break
		if ancestor is ZoneScope:
			zone = ancestor.get_node_or_null("Map") as RenderZone
			break
		ancestor = ancestor.get_parent()
	if zone == null:
		return
	var has_mesh := false
	for item: int in grid.mesh_library.get_item_list():
		if grid.mesh_library.get_item_mesh(item) != null:
			has_mesh = true
			break
	if not has_mesh:
		return
	# Native baking appends to existing instances. Reentry must replace them.
	grid.clear_baked_meshes()
	grid.make_baked_meshes(false)
	var meshes := grid.get_bake_meshes()
	var instances: Array[RID] = []
	for index: int in meshes.size() / 2:
		var instance := grid.get_bake_mesh_instance(index)
		RenderingServer.instance_set_layer_mask(instance, zone.render_mask())
		instances.append(instance)
	_gridmaps[id] = {"node": grid, "instances": instances, "mask": zone.render_mask()}
	_registered[id] = true
	grid.tree_exiting.connect(_unregister.bind(id))


func _register_added(reference: WeakRef) -> void:
	# Socket attachment frees cap visuals synchronously during procedural builds.
	# Resolve a weak reference after the build instead of passing a freed typed Node.
	var node := reference.get_ref() as Node
	if is_instance_valid(node):
		_register(node, true)
