class_name CarWreck
extends CSGCombiner3D
## An abandoned car built from primitives (no vehicle model exists in the asset
## pack). `body_color` and `damaged` let `feature.tscn` place the same scene
## dozens of times and still get visual variety cheaply.

@export var body_color: Color = Color(0.35, 0.37, 0.4)
@export var damaged: bool = false

@onready var _body: CSGBox3D = $Body
@onready var _cabin: CSGBox3D = $Cabin
@onready var _hood: CSGBox3D = $Hood
@onready var _trunk: CSGBox3D = $Trunk


func _ready() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = body_color
	paint.roughness = 0.75 if damaged else 0.45
	paint.metallic = 0.0 if damaged else 0.15
	_body.material = paint
	_cabin.material = paint
	_trunk.material = paint
	if damaged:
		_hood.visible = false
		_hood.use_collision = false
		_cabin.rotation_degrees.z = 2.5
