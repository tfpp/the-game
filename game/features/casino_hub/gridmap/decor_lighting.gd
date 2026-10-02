@tool
extends GridMap
## Cosmetic local lights follow the fixture cells, including GridMap editor changes.

const Decor := preload("res://features/casino_hub/gridmap/decor.gd")
@export var sconce_energy := 1.8
@export var pendant_energy := 2.6
var _stamp := 0
var _elapsed := 0.0


func _ready() -> void:
	_update_lights()
	set_process(Engine.is_editor_hint())


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		_update_lights()


func _update_lights() -> void:
	var cells := get_used_cells()
	var signature: Array = [sconce_energy, pendant_energy]
	for cell: Vector3i in cells:
		signature.append([cell, get_cell_item(cell), get_cell_item_orientation(cell)])
	var stamp := signature.hash()
	if stamp == _stamp and has_node("FixtureLights"):
		return
	_stamp = stamp
	var previous := get_node_or_null("FixtureLights")
	if previous != null:
		remove_child(previous)
		previous.free()
	var lights := Node3D.new()
	lights.name = "FixtureLights"
	add_child(lights)
	for cell: Vector3i in cells:
		var item := get_cell_item(cell)
		if item != Decor.WALL_LIGHT and item != Decor.PENDANT:
			continue
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp_%d_%d_%d" % [cell.x, cell.y, cell.z]
		lamp.position = map_to_local(cell)
		lamp.light_color = Color(1, 0.76, 0.48)
		lamp.light_specular = 0.0
		lamp.omni_attenuation = 1.35
		if item == Decor.WALL_LIGHT:
			lamp.position += get_cell_item_basis(cell) * Vector3(0, 0.1, 0.8)
			lamp.light_energy = sconce_energy
			lamp.omni_range = _sconce_range(cell)
		else:
			lamp.position.y -= 1.2
			lamp.light_energy = pendant_energy
			lamp.omni_range = 8.0
		lights.add_child(lamp)
		# Two bounded shadow lights give the bar and card tables contact and depth.
		if item == Decor.PENDANT and (cell == Vector3i(-7, 20, -10) or cell == Vector3i(-6, 20, 4)):
			var spot := SpotLight3D.new()
			spot.name = "TablePool_%d_%d" % [cell.x, cell.z]
			spot.position = lamp.position
			spot.rotation_degrees.x = -90
			spot.light_color = lamp.light_color
			spot.light_energy = 2.0
			spot.light_specular = 0.0
			spot.spot_range = 9.0
			spot.spot_angle = 65.0
			spot.shadow_enabled = true
			lights.add_child(spot)


func _sconce_range(cell: Vector3i) -> float:
	var outer := absi(cell.x) == 24 or cell.z == -20
	outer = outer or (cell.z == 20 and get_cell_item_basis(cell).z.z < 0)
	if outer:
		return 13.0
	return 6.5 if absi(cell.x) == 2 else 8.0
