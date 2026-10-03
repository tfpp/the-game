extends PatronModel
## Character costumes on the existing connected avatar, not another humanoid mesh.

@export_enum("Tuong Lu Kim", "Junichi Takayama") var character := 0
var _since := 0.0
var _bubble: Label3D
var _rivalry: Node3D


func _ready() -> void:
	dress_up(
		{
			"skin": 2,
			"hair": "bald" if character == 0 else "classic",
			"hair_color": 0,
			"shirt": 0,
			"pants": 3 if character == 0 else 1,
			"tie": -1
		}
	)
	scale = Vector3(1.25, 0.9, 1.15)
	if character == 0:
		_kim_costume()
	else:
		_junichi_costume()
	_name_tag("Tuong Lu Kim" if character == 0 else "Junichi Takayama")
	_bubble = Label3D.new()
	_bubble.name = "Shout"
	_bubble.position.y = 2.65
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font_size = 36
	_bubble.outline_size = 10
	_bubble.pixel_size = 0.004
	_bubble.modulate = Color(1, 0.9, 0.55)
	_bubble.visible = false
	add_child(_bubble)
	_rivalry = get_tree().get_first_node_in_group(&"mall_rivalry") as Node3D
	pose(0.0, 0.0, 0.0, 0.0, 0.0)


func _process(delta: float) -> void:
	_since += delta
	if _since < 0.1:
		return
	var elapsed := _since
	_since = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(global_position) > 900.0:
		_bubble.visible = false
		return
	var shouting: bool = is_instance_valid(_rivalry) and _rivalry.bubble_visible(character)
	_bubble.visible = shouting
	if shouting:
		_bubble.text = _rivalry.LINES[_rivalry.net_turn].replace("! ", "!\n")
	pose(elapsed, 0.0, 0.0, 0.0, 0.0)
	if shouting:
		reach(0.9)
		avatar._head.rotation.x = -0.15
		avatar.human.pose(avatar, false, false)


func _kim_costume() -> void:
	var orange := _material(Color("ce7234"))
	var red := _material(Color("a82727"))
	var black := _material(Color("161619"))
	for side: float in [-1.0, 1.0]:
		_part(
			"Vest%d" % int(side),
			torso_items,
			Vector3(side * .1, .36, CHEST_Z - .012),
			Vector3(.15, .38, .035),
			orange
		)
		_part(
			"Bow%d" % int(side),
			torso_items,
			Vector3(side * .035, .56, CHEST_Z - .03),
			Vector3(.06, .035, .025),
			red
		)
		_part(
			"SideHair%d" % int(side),
			head_items,
			Vector3(side * .085, .27, .01),
			Vector3(.025, .09, .15),
			black
		)
	_part("VestBack", torso_items, Vector3(0, .36, .11), Vector3(.33, .38, .025), orange)
	_part(
		"Tooth",
		head_items,
		Vector3(0, .13, FACE_Z - .016),
		Vector3(.024, .027, .015),
		_material(Color("f0eee5"))
	)
	for strip: int in 3:
		_part(
			"CombOver%d" % strip,
			head_items,
			Vector3(0, .32, -.02 + strip * .035),
			Vector3(.17, .008, .008),
			black
		)
	var badge := Label3D.new()
	badge.text = "CITY\nWOK"
	badge.font_size = 24
	badge.pixel_size = .0012
	badge.position = Vector3(-.10, .38, CHEST_Z - .034)
	badge.rotation.y = PI
	torso_items.add_child(badge)


func _junichi_costume() -> void:
	var white := _material(ClothingCatalog.COLORS[0])
	var black := _material(Color("161619"))
	# Broad overlapping gi lapels and black waist sash distinguish the sushi owner.
	for side: float in [-1.0, 1.0]:
		var lapel := _part(
			"GiLapel%d" % int(side),
			torso_items,
			Vector3(side * .065, .44, CHEST_Z - .02),
			Vector3(.045, .28, .03),
			white
		)
		lapel.rotation.z = side * .38
	_part("Sash", torso_items, Vector3(0, .20, 0), Vector3(.35, .055, .25), black)
	_part(
		"SashKnot", torso_items, Vector3(.03, .19, CHEST_Z - .025), Vector3(.065, .07, .04), black
	)
