extends Node3D

const HOTEL := preload("res://features/street_hotel/feature.tscn")
const PRESENTATION := preload("res://features/street_district/presentation.gd")
const PLAYER := preload("res://core/player/player.tscn")


func _ready() -> void:
	PRESENTATION.add(self)
	var hotel := HOTEL.instantiate() as Node3D
	add_child(hotel)
	var floor := hotel.get_node("Floors/Floor01") as StreamedRoom
	floor.load_room(3000)
	var player := PLAYER.instantiate() as Player
	player.position = (floor.get_node("Arrival") as Marker3D).global_position
	player.yaw = PI
	add_child(player)
	Controls.playing = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Controls.playing = false
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Controls.playing = true
