extends Node3D

const LAYOUT := preload("res://features/street_district/layout.gd")
const OBJECTS := preload("res://features/street_district/street_objects.tscn")
const PRESENTATION := preload("res://features/street_district/presentation.gd")
const PLAYER := preload("res://core/player/player.tscn")


func _ready() -> void:
	LAYOUT.build(self)
	add_child(OBJECTS.instantiate())
	PRESENTATION.add(self)
	var player := PLAYER.instantiate() as Player
	player.position = Vector3(0, .1, 3)
	player.yaw = PI
	add_child(player)
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	Controls.playing = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.text = (
		"STREET DISTRICT\nWASD / mouse / Space jump / Esc release\n"
		+ "Streets loop around four blocks; alleys provide shortcuts."
	)
	label.position = Vector2(20, 20)
	canvas.add_child(label)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Controls.playing = false
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Controls.playing = true
