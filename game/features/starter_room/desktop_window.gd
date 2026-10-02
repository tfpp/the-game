class_name GarageDesktopWindow
extends PanelContainer
## Feature-local window geometry; never changes gameplay or another peer's UI.

signal activated

var preferred_size := Vector2(580, 390)
var initial_position := Vector2(32, 24)
var maximized := false
var _initialized := false
var _restored := Rect2()
var _gesture := ""
var _pointer := -1
var _origin := Vector2.ZERO
var _start_rect := Rect2()


func _ready() -> void:
	get_parent().resized.connect(fit_workspace)
	visibility_changed.connect(cancel_gesture)
	fit_workspace.call_deferred()


func fit_workspace() -> void:
	var bounds := (get_parent() as Control).size
	if bounds.x <= 0 or bounds.y <= 0:
		return
	if not _initialized:
		size = preferred_size.min(bounds)
		position = initial_position
		_initialized = true
	if maximized:
		position = Vector2.ZERO
		size = bounds
	else:
		size = size.min(bounds)
		position = position.clamp(Vector2.ZERO, (bounds - size).max(Vector2.ZERO))


func toggle_maximize() -> void:
	cancel_gesture()
	if maximized:
		maximized = false
		position = _restored.position
		size = _restored.size
	else:
		_restored = Rect2(position, size)
		maximized = true
	fit_workspace()
	activated.emit()


func cancel_gesture() -> void:
	_gesture = ""
	_pointer = -1


func begin_gesture(event: InputEvent, kind: String, handle: Control = null) -> void:
	if maximized:
		return
	var point := Vector2.ZERO
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		point = event.position
		_pointer = -1
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
		point = event.position
		_pointer = event.index
	else:
		return
	# gui_input delivers handle-local positions; _input motion uses viewport positions.
	if handle != null:
		point = handle.get_global_transform_with_canvas() * point
	activated.emit()
	_gesture = kind
	_origin = _workspace_point(point)
	_start_rect = Rect2(position, size)
	accept_event()


func _workspace_point(point: Vector2) -> Vector2:
	return (get_parent() as Control).get_global_transform_with_canvas().affine_inverse() * point


func _activate_at(hit: Vector2) -> void:
	if not Rect2(position, size).has_point(hit):
		return
	# Only the topmost window under this point may claim focus.
	for sibling: Node in get_parent().get_children():
		if sibling is GarageDesktopWindow and sibling.visible:
			if (
				sibling.get_index() > get_index()
				and Rect2(sibling.position, sibling.size).has_point(hit)
			):
				return
	activated.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		cancel_gesture()
		return
	if _gesture.is_empty():
		# Raise the window even when clicking an editor or a child button.
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			_activate_at(_workspace_point(event.position))
		return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and _pointer == -1:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			cancel_gesture()
		return
	if event is InputEventScreenTouch and event.index == _pointer:
		if not event.pressed:
			cancel_gesture()
		return
	if event is InputEventMouseMotion and _pointer == -1:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			cancel_gesture()
			return
		point = event.position
	elif event is InputEventScreenDrag and event.index == _pointer:
		point = event.position
	else:
		return
	var delta := _workspace_point(point) - _origin
	if _gesture == "move":
		position = _start_rect.position + delta
	else:
		size = (_start_rect.size + delta).max(Vector2(300, 220))
	fit_workspace()
	get_viewport().set_input_as_handled()
