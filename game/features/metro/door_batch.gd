class_name MetroDoorBatch
extends MultiMeshInstance3D
## One draw batch per car's identical door leaves; animation still owns the poses.

@export var door_paths: Array[NodePath] = []
@export var visual_transforms: Array[Transform3D] = []
var _doors: Array[Node3D] = []


func _ready() -> void:
	# Each train has independently animated doors even when its mesh is shared.
	# Allocate the poses afresh: the headless renderer has no buffer to duplicate.
	var shared_mesh := multimesh.mesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = shared_mesh
	multimesh.instance_count = door_paths.size()
	for path: NodePath in door_paths:
		_doors.append(get_node(path) as Node3D)
	sync_doors()


func sync_doors() -> void:
	for index: int in _doors.size():
		multimesh.set_instance_transform(index, _doors[index].transform * visual_transforms[index])
