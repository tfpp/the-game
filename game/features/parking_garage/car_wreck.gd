class_name CarWreck
extends StaticBody3D
## Vertex-authored sedan shell with a simple stable collision volume. Each
## instance keeps its own faded paint, while the trim mesh is shared.

@export var body_color: Color = Color(0.35, 0.37, 0.4)
@export var damaged: bool = false

@onready var _body: MeshInstance3D = $BodyPaint
@onready var _hood: MeshInstance3D = $HoodPaint
@onready var _boot: MeshInstance3D = $BootLid


func _ready() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = body_color.darkened(0.18) if damaged else body_color
	paint.roughness = 0.94 if damaged else 0.77
	_body.set_surface_override_material(0, paint)
	_hood.set_surface_override_material(0, paint)
	_boot.set_surface_override_material(0, paint)
	if damaged:
		_hood.visible = false
