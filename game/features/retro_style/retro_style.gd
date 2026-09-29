class_name RetroStyle
extends Node
## Apply the same inexpensive art direction to existing and streamed 3D props.
## UI, font atlases and arcade screen shaders keep their own sampling and resolution.

const MOBILE_HEIGHT := 432.0
const MOBILE_MAX_SCALE := 0.7
const BATCH_SIZE := 64
const MOBILE_LOCAL_LIGHTS := 2
const MOBILE_PROP_DISTANCE := 40.0
## Slow phones skip physics catch-up instead of spiralling into longer frames.
const MOBILE_MAX_PHYSICS_STEPS := 2

var mobile := false
var _pending: Array[WeakRef] = []
# Weak references avoid retaining unloaded streamed-room resources.
var _materials: Dictionary[int, WeakRef] = {}
var _meshes: Dictionary[int, WeakRef] = {}
var _lights: Array[Dictionary] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	mobile = is_mobile_device() or "--retro-mobile" in OS.get_cmdline_user_args()
	_configure_viewport()
	get_viewport().size_changed.connect(_configure_viewport)
	get_tree().node_added.connect(_queue_node)
	_queue_tree(get_tree().root)
	if mobile:
		Engine.max_physics_steps_per_frame = MOBILE_MAX_PHYSICS_STEPS
		var budget_timer := Timer.new()
		budget_timer.wait_time = 0.25
		budget_timer.timeout.connect(_update_light_budget)
		add_child(budget_timer)
		budget_timer.start()


static func is_mobile_device() -> bool:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		return bool(
			JavaScriptBridge.eval(
				(
					"/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)"
					+ " || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)"
				)
			)
		)
	return false


static func mobile_scale(viewport_size: Vector2) -> float:
	return minf(MOBILE_MAX_SCALE, MOBILE_HEIGHT / maxf(viewport_size.y, 1.0))


func _configure_viewport() -> void:
	if not mobile:
		return
	var viewport := get_viewport()
	var window := get_window()
	# Use framebuffer dimensions, not the stretched UI's virtual rectangle.
	# Portrait otherwise gets an accidentally tiny 3D buffer and unreadable UI.
	var portrait := window.size.x < window.size.y
	var ui_size := Vector2i(480, 720) if portrait else Vector2i(960, 540)
	if window.content_scale_size != ui_size:
		window.content_scale_size = ui_size
	viewport.scaling_3d_scale = 1.0 if viewport.use_xr else mobile_scale(Vector2(window.size))
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false


func _queue_tree(node: Node) -> void:
	_queue_node(node)
	for child: Node in node.get_children():
		_queue_tree(child)


func _queue_node(node: Node) -> void:
	if node is GeometryInstance3D or node is Light3D or node is WorldEnvironment:
		_pending.append(weakref(node))
		set_process(true)


func _process(_delta: float) -> void:
	for index: int in mini(BATCH_SIZE, _pending.size()):
		var node := (_pending.pop_back() as WeakRef).get_ref() as Node
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			style_node(node)
	if _pending.is_empty():
		for cache: Dictionary in [_materials, _meshes]:
			for id: int in cache.keys():
				if cache[id].get_ref() == null:
					cache.erase(id)
		set_process(false)


func style_node(node: Node) -> void:
	if node is WorldEnvironment:
		var environment: Environment = node.environment
		if environment != null:
			environment.glow_enabled = false
			environment.ssao_enabled = false
			environment.ssr_enabled = false
			environment.ssil_enabled = false
	elif node is Light3D:
		node.light_specular = 0.0
		if mobile:
			node.shadow_enabled = false
			if node is OmniLight3D or node is SpotLight3D:
				_lights.append({"light": weakref(node), "mask": node.light_cull_mask})
				node.light_cull_mask = 0
	elif node is GeometryInstance3D:
		_style_material(node.material_override)
		if node is MeshInstance3D and node.mesh != null:
			_style_mesh(node.mesh)
			if mobile and node.mesh.get_aabb().size.length() < 8.0:
				node.visibility_range_end = MOBILE_PROP_DISTANCE
				node.visibility_range_end_margin = 4.0
			for surface: int in node.mesh.get_surface_count():
				_style_material(node.get_surface_override_material(surface))
		elif node is CSGPrimitive3D:
			_style_material(node.material)


func _style_material(material: Material) -> void:
	if not material is BaseMaterial3D or _seen(_materials, material):
		return
	var surface := material as BaseMaterial3D
	if surface.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		surface.shading_mode = (
			BaseMaterial3D.SHADING_MODE_PER_PIXEL
			if surface.get_meta(&"per_pixel_lighting", false)
			else BaseMaterial3D.SHADING_MODE_PER_VERTEX
		)
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	surface.metallic = 0.0
	surface.metallic_specular = 0.0
	surface.roughness = 1.0
	surface.normal_enabled = false
	surface.roughness_texture = null
	surface.normal_texture = null


func _style_mesh(mesh: Mesh) -> void:
	if _seen(_meshes, mesh):
		return
	if mesh is SphereMesh:
		mesh.radial_segments = mini(mesh.radial_segments, 12)
		mesh.rings = mini(mesh.rings, 6)
	elif mesh is CylinderMesh:
		mesh.radial_segments = mini(mesh.radial_segments, 12)
		mesh.rings = mini(mesh.rings, 1)
	for surface: int in mesh.get_surface_count():
		_style_material(mesh.surface_get_material(surface))


func _seen(cache: Dictionary[int, WeakRef], resource: Resource) -> bool:
	var id := resource.get_instance_id()
	if cache.has(id) and cache[id].get_ref() == resource:
		return true
	cache[id] = weakref(resource)
	return false


func _update_light_budget() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var candidates: Array[Dictionary] = []
	for index: int in range(_lights.size() - 1, -1, -1):
		var entry: Dictionary = _lights[index]
		var light := (entry["light"] as WeakRef).get_ref() as Light3D
		if light == null or light.is_queued_for_deletion():
			_lights.remove_at(index)
			continue
		light.light_cull_mask = 0
		if not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		var radius: float = light.omni_range if light is OmniLight3D else light.spot_range
		if light.global_position.distance_to(camera.global_position) < radius + 12.0:
			candidates.append({"light": light, "mask": entry["mask"]})
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var first := a["light"] as Light3D
			var second := b["light"] as Light3D
			return (
				first.global_position.distance_squared_to(camera.global_position)
				< second.global_position.distance_squared_to(camera.global_position)
			)
	)
	for index: int in mini(MOBILE_LOCAL_LIGHTS, candidates.size()):
		var chosen := candidates[index]["light"] as Light3D
		chosen.light_cull_mask = int(candidates[index]["mask"])
