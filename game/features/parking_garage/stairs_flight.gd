class_name StairsFlight
extends Node3D
## Builds a straight flight of concrete steps at ready by stacking full-depth
## risers (each step is a box reaching all the way to the ground, one step
## taller than the last), so `feature.tscn` needs one node per flight instead
## of dozens of hand-placed boxes. Steps run along local -Z as they rise.

@export var step_count: int = 22
@export var rise: float = 0.15
@export var run: float = 0.2727
@export var width: float = 3.0
@export var material: Material


func _ready() -> void:
	for i in step_count:
		var step := CSGBox3D.new()
		var height := rise * float(i + 1)
		step.size = Vector3(width, height, run)
		step.position = Vector3(0, height * 0.5, -run * (float(i) + 0.5))
		step.material = material
		step.use_collision = true
		add_child(step)
