extends Node3D
## Static geometry built only inside the local player's StreamedRoom.

const CHROME := preload("res://features/casino_hub/materials/chrome.tres")
const WALL := preload("res://features/casino_hub/materials/wallpaper.tres")
const WOOD := preload("res://features/casino_hub/materials/wood.tres")
const CARPET := preload("res://features/casino_hub/materials/carpet.tres")
const PLASTER := preload("res://features/casino_hub/materials/plaster.tres")
const BRASS := preload("res://features/casino_hub/materials/brass.tres")

@export var lobby := false


func _ready() -> void:
	if lobby:
		_build_lobby()
	else:
		_build_floor()


func _shell(width: float, depth: float) -> void:
	_box("Floor", Vector3(0, -0.15, 0), Vector3(width, 0.3, depth), CARPET)
	_box("Ceiling", Vector3(0, 3.65, 0), Vector3(width, 0.3, depth), PLASTER)
	for side: float in [-1.0, 1.0]:
		_box("Wall", Vector3(side * width / 2, 1.75, 0), Vector3(0.2, 3.5, depth), WALL)
		_box("Wall", Vector3(0, 1.75, side * depth / 2), Vector3(width, 3.5, 0.2), WALL)


func _build_lobby() -> void:
	_shell(16, 14)
	_box("Desk", Vector3(0, 0.6, -3), Vector3(4, 1.2, 1.2), WOOD)
	_box("Counter", Vector3(0, 1.25, -3), Vector3(4.3, 0.1, 1.4), BRASS)
	_elevator_frame(Vector3(5, 0, -6), 0)
	_sign("LILY APARTMENTS\nFRONT DESK · FREE ROOMS", Vector3(0, 2.9, -6.89))
	_sign("EXPRESS ELEVATOR\nYour floor ↑", Vector3(5, 2.8, -5.9))
	_sign("CASINO", Vector3(-5, 2.8, 6.89)).rotation.y = PI
	for x: float in [-5.0, 5.0]:
		_box("Bench", Vector3(x, 0.35, 1), Vector3(2.4, 0.7, 0.8), WOOD)


func _build_floor() -> void:
	_shell(32.4, 18)
	_elevator_frame(Vector3(-16, 0, 0), PI / 2)
	var number := int(get_parent().get_meta(&"floor_number", 1))
	var floor_sign := _sign("FLOOR %d\nELEVATOR TO RECEPTION" % number, Vector3(-15.8, 2.9, 0))
	floor_sign.rotation.y = PI / 2
	for slot: int in 10:
		var x := -12.0 + (slot % 5) * 6.0
		var side := -1.0 if slot < 5 else 1.0
		var center := Vector3(x, 0, side * 5.5)
		# 2m open doorway off a 4m corridor; no locks or private instancing.
		for offset: float in [-2.0, 2.0]:
			_box("DoorWall", Vector3(x + offset, 1.75, side * 2), Vector3(2, 3.5, 0.2), WALL)
		_box("Lintel", Vector3(x, 3, side * 2), Vector3(2, 1, 0.2), WOOD)
		_box("Partition", Vector3(x - 3, 1.75, side * 5.5), Vector3(0.2, 3.5, 7), WALL)
		var unit_sign := _sign("UNIT %d%02d" % [number, slot + 1], Vector3(x, 2.8, side * 1.85))
		unit_sign.rotation.y = PI if side > 0 else 0.0
		_box("BedFrame", center + Vector3(-1.7, 0.3, side), Vector3(1.8, 0.6, 2.8), WOOD)
		_box("Mattress", center + Vector3(-1.7, 0.7, side), Vector3(1.7, 0.2, 2.7), PLASTER)
		_box("Pillow", center + Vector3(-1.7, 0.85, side * 1.8), Vector3(1.3, 0.1, 0.55), CARPET)
		_box("Table", center + Vector3(1.7, 0.5, 1), Vector3(1.1, 1, 1.1), WOOD)
		_box("Kitchen", Vector3(x + 1.5, 0.5, side * 8.2), Vector3(2.5, 1, 0.8), WOOD)
		_box("Worktop", Vector3(x + 1.5, 1.05, side * 8.2), Vector3(2.6, 0.1, 0.9), PLASTER)
		_box("Window", Vector3(x, 2.1, side * 8.85), Vector3(2.8, 1.4, 0.05), BRASS)
	_box("EndPartition", Vector3(15, 1.75, -5.5), Vector3(0.2, 3.5, 7), WALL)
	_box("EndPartition", Vector3(15, 1.75, 5.5), Vector3(0.2, 3.5, 7), WALL)


func _box(title: String, point: Vector3, size: Vector3, material: Material) -> void:
	var box := CSGBox3D.new()
	box.name = title
	box.position = point
	box.size = size
	box.material = material
	box.use_collision = true
	add_child(box)


func _sign(words: String, point: Vector3) -> SignBoard:
	var label := SignBoard.new()
	label.position = point
	label.text = words
	label.letter_height = .14
	label.padding = .035
	add_child(label)
	return label


func _elevator_frame(point: Vector3, angle: float) -> void:
	var frame := Node3D.new()
	frame.position = point
	frame.rotation.y = angle
	for offset: float in [-1.1, 1.1]:
		var post := CSGBox3D.new()
		post.size = Vector3(0.2, 2.6, 0.3)
		post.position = Vector3(offset, 1.3, 0)
		post.material = CHROME
		frame.add_child(post)
	var seam := CSGBox3D.new()
	seam.size = Vector3(0.025, 2.4, 0.2)
	seam.position = Vector3(0, 1.2, 0)
	seam.material = WOOD
	frame.add_child(seam)
	var button := CSGBox3D.new()
	button.size = Vector3(0.15, 0.3, 0.12)
	button.position = Vector3(1.4, 1.2, 0)
	button.material = BRASS
	frame.add_child(button)
	add_child(frame)
