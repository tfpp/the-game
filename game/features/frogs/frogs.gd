extends Node3D
## Server-owned spawning. Every peer receives the same appearance and movement
## profile, while each frog chooses its own safe route through the level.

const FROG_SCENE := preload("res://features/frogs/frog.tscn")
const FROG_COUNT := 12

## Optional authored colony; empty keeps the original random pond spawning.
@export var spawn_points := PackedVector3Array()
@export_range(0.1, 2.0) var profile_scale := 1.0

@onready var _pond: Node3D = $Pond
@onready var _spawner: MultiplayerSpawner = $FrogSpawner


func _ready() -> void:
	_spawner.spawn_function = _spawn_frog
	Network.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_clear_frogs()
	if Network.is_authoritative():
		_spawn_frogs()


func _spawn_frogs() -> void:
	var count := FROG_COUNT if spawn_points.is_empty() else spawn_points.size()
	for index: int in count:
		var start := (
			FrogHop.pick_target(Vector3.ZERO, FrogHop.HOP_RADIUS, randf() * TAU, randf())
			if spawn_points.is_empty()
			else spawn_points[index]
		)
		var profile := FrogHop.profile_for_index(index)
		for key: String in ["size", "distance", "height"]:
			profile[key] *= profile_scale
		_spawner.spawn(
			{
				"index": index,
				"position": start,
				"color": FrogHop.color_for_index(index),
				"profile": profile
			}
		)


## Runs on every peer (spawn_function), so each frog looks identical everywhere.
func _spawn_frog(data: Variant) -> Node:
	var info := data as Dictionary
	var frog := FROG_SCENE.instantiate() as Frog
	frog.name = "Frog%d" % int(info["index"])
	frog.position = info["position"]
	frog.body_color = info["color"]
	var profile: Dictionary = info["profile"]
	frog.body_size = profile["size"]
	frog.jump_distance = profile["distance"]
	frog.jump_height = profile["height"]
	frog.jump_duration = profile["duration"]
	frog.rest_time = profile["rest"]
	return frog


func _clear_frogs() -> void:
	for child: Node in _pond.get_children():
		_pond.remove_child(child)
		child.queue_free()
