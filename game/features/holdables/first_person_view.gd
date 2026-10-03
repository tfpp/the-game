class_name FirstPersonView
extends CanvasLayer
## Layer 18 has its own depth buffer; garage visibility owns layers 19 and 20.
## Share the world so handhelds retain the room's lighting and environment.

const MASK := 1 << 17
const ACTIVE_META := &"first_person_visual"
const LAYERS_META := &"first_person_world_layers"
const SHADOW_META := &"first_person_world_shadow"
const SWAP_LOWER_SECONDS := 0.12
const SWAP_RAISE_SECONDS := 0.22

var player: Player
var viewport := SubViewport.new()
var camera := Camera3D.new()
var _image := TextureRect.new()
var _swap_time := SWAP_LOWER_SECONDS + SWAP_RAISE_SECONDS
var _swap_start := 0.0
var _swap_weight := 0.0
var _swap_request := Callable()


static func is_first_person(owner: Player) -> bool:
	return owner.is_local() and not (owner.get_node("Body") as Node3D).visible


static func ensure_for(owner: Player) -> void:
	if not owner.is_local() or owner.has_node("FirstPersonView"):
		return
	var view := FirstPersonView.new()
	view.name = "FirstPersonView"
	view.player = owner
	owner.add_child(view)


static func request_swap(owner: Player, request: Callable) -> void:
	if not is_first_person(owner):
		request.call()
		return
	ensure_for(owner)
	var view := owner.get_node("FirstPersonView") as FirstPersonView
	view._swap_start = view._swap_weight
	view._swap_time = 0.0
	# Rapid scrolling replaces the pending selection and lowers from the current
	# pose, so it never queues a string of animations or snaps back upright.
	view._swap_request = request


static func swap_pose(owner: Player) -> Transform3D:
	var view := owner.get_node_or_null("FirstPersonView") as FirstPersonView
	var weight := view._swap_weight if view != null else 0.0
	return Transform3D(
		Basis(Vector3.RIGHT, -weight * 0.35), Vector3(0.0, -weight * 0.6, weight * 0.12)
	)


static func firing_blocked(tree: SceneTree, peer_id: int) -> bool:
	var owner := tree.get_first_node_in_group(&"local_player") as Player
	if owner == null or owner.get_multiplayer_authority() != peer_id:
		return false
	var view := owner.get_node_or_null("FirstPersonView") as FirstPersonView
	return view != null and view._swap_time < SWAP_LOWER_SECONDS + SWAP_RAISE_SECONDS


func _advance_swap(delta: float) -> void:
	_swap_time += delta
	if _swap_time < SWAP_LOWER_SECONDS:
		var lower := smoothstep(0.0, SWAP_LOWER_SECONDS, _swap_time)
		_swap_weight = lerpf(_swap_start, 1.0, lower)
		return
	if _swap_request.is_valid():
		var request := _swap_request
		_swap_request = Callable()
		request.call()
	var raise := smoothstep(
		SWAP_LOWER_SECONDS, SWAP_LOWER_SECONDS + SWAP_RAISE_SECONDS, _swap_time
	)
	_swap_weight = 1.0 - raise


static func set_visuals(node: Node, first_person: bool) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if not geometry.has_meta(LAYERS_META):
			geometry.set_meta(LAYERS_META, geometry.layers)
			geometry.set_meta(SHADOW_META, geometry.cast_shadow)
		geometry.set_meta(ACTIVE_META, first_person)
		geometry.layers = MASK if first_person else int(geometry.get_meta(LAYERS_META))
		geometry.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if first_person
			else int(geometry.get_meta(SHADOW_META))
		)
	for child: Node in node.get_children():
		set_visuals(child, first_person)


func _ready() -> void:
	layer = 0  # Below HUD, crosshair and menus.
	process_priority = 30
	viewport.name = "HandheldViewport"
	viewport.transparent_bg = true
	viewport.world_3d = player.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera.cull_mask = MASK
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = 0.01
	camera.far = 10.0
	viewport.add_child(camera)
	camera.current = true
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.texture = viewport.get_texture()
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_image)


func _process(delta: float) -> void:
	_advance_swap(delta)
	var source := player.get_node("Camera") as Camera3D
	# Run after room visibility, which also updates the world's camera mask.
	var active_camera := player.get_viewport().get_camera_3d()
	if active_camera != null:
		active_camera.cull_mask &= ~MASK
	var active := is_first_person(player) and active_camera == source
	_image.visible = active
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)
	if not active:
		return
	viewport.size = Vector2i(player.get_viewport().get_visible_rect().size)
	viewport.msaa_3d = player.get_viewport().msaa_3d
	camera.global_transform = source.global_transform
	camera.fov = source.fov
	camera.keep_aspect = source.keep_aspect
	camera.projection = source.projection
	camera.size = source.size
	camera.h_offset = source.h_offset
	camera.v_offset = source.v_offset
	camera.environment = source.environment
	camera.attributes = source.attributes
