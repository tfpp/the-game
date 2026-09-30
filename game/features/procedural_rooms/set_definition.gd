class_name ProceduralSetDefinition
extends Resource
## Floor-centred reusable furnishing with a conservative clearance footprint.

@export var id := ""
@export var scene: PackedScene
@export var footprint := Vector3(2, 3, 2)
@export var allowed_rooms: Array[String] = []
