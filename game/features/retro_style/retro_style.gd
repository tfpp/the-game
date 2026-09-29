class_name RetroStyle
extends Node
## Apply the same inexpensive art direction to existing and streamed 3D props.
## UI, font atlases and arcade screen shaders keep their own sampling and resolution.

const BATCH_SIZE := 64
## Slow phones skip physics catch-up instead of spiralling into longer frames.
const MOBILE_MAX_PHYSICS_STEPS := 2

var mobile := false
var _pending: Array[WeakRef] = []
# Weak references avoid retaining unloaded streamed-room resources.
var _materials: Dictionary[int, WeakRef] = {}
var _meshes: Dictionary[int, WeakRef] = {}


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


func _configure_viewport() -> void:
	if not mobile:
		return
	var window := get_window()
	# Keep touch UI readable in either orientation without changing 3D settings.
	var portrait := window.size.x < window.size.y
	var ui_size := Vector2i(480, 720) if portrait else Vector2i(960, 540)
	if window.content_scale_size != ui_size:
		window.content_scale_size = ui_size


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
	elif node is GeometryInstance3D:
		_style_material(node.material_override)
		if node is MeshInstance3D and node.mesh != null:
			_style_mesh(node.mesh)
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
