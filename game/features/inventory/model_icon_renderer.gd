class_name ModelIconRenderer
extends Node
## One private viewport renders queued model thumbnails once; UI controls share cached textures.

signal rendered(key: String, texture: Texture2D)

const RESOLUTION := 128
const CACHE_LIMIT := 128
const GROUP := &"model_icon_renderers"

var _cache: Dictionary[String, Texture2D] = {}
var _pending: Dictionary[String, bool] = {}
var _jobs: Array[Dictionary] = []
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _busy := false


static func for_control(control: Control) -> ModelIconRenderer:
	var viewport := control.get_viewport()
	var existing: ModelIconRenderer
	if viewport.has_meta("inventory_model_icons"):
		existing = viewport.get_meta("inventory_model_icons") as ModelIconRenderer
	if is_instance_valid(existing):
		return existing
	var renderer := ModelIconRenderer.new()
	viewport.set_meta("inventory_model_icons", renderer)
	viewport.add_child.call_deferred(renderer)
	return renderer


func _ready() -> void:
	add_to_group(GROUP)
	if DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world.add_child(_camera)
	_camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.0
	_world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("dce4ed")
	environment.environment.ambient_light_energy = .75
	_world.add_child(environment)
	if not _jobs.is_empty():
		_busy = true
		_render_next.call_deferred()


func request_item(id: String) -> Texture2D:
	var definition := ItemCatalog.find(id)
	if definition == null:
		return null
	return _request("item:" + id, ItemCatalog.create_view.bind(id), definition.icon_view_direction)


func request_scene(key: String, scene: PackedScene, direction := Vector3(1, .9, 1)) -> Texture2D:
	if key.is_empty() or scene == null:
		return null
	return _request("scene:" + key, _instantiate.bind(scene), direction)


static func _instantiate(scene: PackedScene) -> Node3D:
	return scene.instantiate() as Node3D


func _request(key: String, factory: Callable, direction: Vector3) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if (
		DisplayServer.get_name() == "headless"
		or _pending.has(key)
		or _cache.size() + _pending.size() >= CACHE_LIMIT
	):
		return null
	_pending[key] = true
	_jobs.append({"key": key, "factory": factory, "direction": direction})
	if not _busy and _viewport != null:
		_busy = true
		_render_next.call_deferred()
	return null


func _render_next() -> void:
	while not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		var key: String = job["key"]
		var factory: Callable = job["factory"]
		var model := factory.call() as Node3D
		if model == null:
			_pending.erase(key)
			continue
		_world.add_child(model)
		# Procedural view scenes may create their geometry in _ready().
		await get_tree().process_frame
		var bounds := model_bounds(model)
		if bounds.size.length_squared() < .000001:
			model.free()
			_pending.erase(key)
			continue
		frame_bounds(_camera, bounds, job["direction"])
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		model.free()
		var texture := ImageTexture.create_from_image(image)
		_cache[key] = texture
		_pending.erase(key)
		rendered.emit(key, texture)
	_busy = false


static func model_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for visual: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if visual.mesh == null or not visual.visible:
			continue
		var transform := (
			root.transform * root.global_transform.affine_inverse() * visual.global_transform
		)
		var box := transform * visual.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


static func frame_bounds(camera: Camera3D, bounds: AABB, direction: Vector3) -> void:
	var center := bounds.get_center()
	var view := direction.normalized()
	if view.length_squared() < .5 or absf(view.dot(Vector3.UP)) > .99:
		view = Vector3(1, .9, 1).normalized()
	camera.position = center + view * maxf(bounds.size.length() * 2, 1.0)
	camera.look_at(center)
	var projected := Rect2()
	for corner: int in 8:
		var point := Vector3(
			bounds.end.x if corner & 1 else bounds.position.x,
			bounds.end.y if corner & 2 else bounds.position.y,
			bounds.end.z if corner & 4 else bounds.position.z
		)
		var relative := camera.basis.inverse() * (point - center)
		projected = projected.expand(Vector2(relative.x, relative.y))
	camera.size = maxf(projected.size.x, projected.size.y) * 1.18
	camera.near = .001
	camera.far = maxf(bounds.size.length() * 6, 10.0)


func _exit_tree() -> void:
	var parent := get_parent()
	if parent != null and parent.has_meta("inventory_model_icons"):
		if parent.get_meta("inventory_model_icons") == self:
			parent.remove_meta("inventory_model_icons")
