extends Node3D
## Server-owned target spawning for the arena's dummies, the same MultiplayerSpawner
## pattern features/frogs/frogs.gd uses for its pond. Every peer gets identical
## dummies in identical spots since positions arrive as spawn data, not simulated
## state — nothing here needs its own per-target synchronizer property.

const TARGET_SCENE := preload("res://features/shooting_gallery/humanoid_target.tscn")

## Local to $Arena/Targets: scattered through the arena rather than lined up in a
## single row, for the Doom-style "targets surround you" arena feel the request
## asked for rather than a straight shooting-range line.
const TARGET_SPAWNS: Array[Vector3] = [
	Vector3(0, 0, -9),
	Vector3(-7, 0, -5),
	Vector3(7, 0, -5),
	Vector3(-9, 0, 1),
	Vector3(9, 0, 1),
	Vector3(0, 0, -2),
]

const JUMPSUIT_COLORS: Array[Color] = [
	Color(0.55, 0.35, 0.15),
	Color(0.2, 0.32, 0.22),
	Color(0.24, 0.24, 0.28),
	Color(0.5, 0.15, 0.15),
	Color(0.18, 0.28, 0.42),
	Color(0.45, 0.38, 0.12),
]

@onready var _targets: Node3D = $Arena/Targets
@onready var _spawner: MultiplayerSpawner = $Arena/TargetSpawner


func _ready() -> void:
	_spawner.spawn_function = _spawn_target
	Network.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_clear_targets()
	if Network.is_authoritative():
		_spawn_targets()


func _spawn_targets() -> void:
	for index: int in TARGET_SPAWNS.size():
		_spawner.spawn({"index": index, "position": TARGET_SPAWNS[index]})


## Runs on every peer (spawn_function), so each dummy looks identical everywhere.
func _spawn_target(data: Variant) -> Node:
	var info := data as Dictionary
	var index := int(info["index"])
	var target := TARGET_SCENE.instantiate() as HumanoidTarget
	target.name = "Target%d" % index
	target.position = info["position"]
	# Face south, back toward the entrance the player walks in from.
	target.rotation.y = PI
	target.jumpsuit_color = JUMPSUIT_COLORS[index % JUMPSUIT_COLORS.size()]
	return target


func _clear_targets() -> void:
	for child: Node in _targets.get_children():
		_targets.remove_child(child)
		child.queue_free()
