extends SceneTree
## Offline shop dressing: existing merchandise models and the modeled signage kit.

const SHELF := preload("res://features/pawn_shop/models/shop_shelves.tscn")
const SIGN := preload("res://features/signage/sign_board.tscn")
const TV := preload("res://features/hotel_props/props/crt_television.tscn")
const RADIO := preload("res://features/hotel_props/props/bedside_radio.tscn")
const PHONE := preload("res://features/hotel_props/props/rotary_phone.tscn")
const CLOCK := preload("res://features/hotel_props/props/alarm_clock.tscn")
const CASE := preload("res://features/hotel_props/props/vintage_suitcase.tscn")
const FAN := preload("res://features/hotel_props/props/standing_fan.tscn")
const LAMP := preload("res://features/hotel_props/props/table_lamp.tscn")
const BOX := preload("res://features/street_props/props/cardboard_box.tscn")
const TRUNK := preload("res://features/hotel_props/props/steamer_trunk.tscn")
const CHAIR := preload("res://features/hotel_props/props/armchair.tscn")
const TABLE := preload("res://features/hotel_props/props/coffee_table.tscn")
const ART := preload("res://features/hotel_props/props/framed_art.tscn")
const FIXTURE := preload("res://features/street_props/props/fluorescent_fixture.tscn")
const BRASS := preload("res://features/casino_hub/materials/brass.tres")
var _root: Node3D


func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "PawnShopDressing"
	var electronics := _prop(SHELF, "Electronics", Vector3(-15.5, 0, 23), PI / 2)
	_stock(electronics, TV, "TV1", Vector3(-.62, .96, 0))
	_stock(electronics, TV, "TV2", Vector3(.52, .96, 0))
	_stock(electronics, TV, "TV3", Vector3(-.6, 1.74, 0))
	_stock(electronics, RADIO, "Radio1", Vector3(.38, 1.74, .1))
	_stock(electronics, RADIO, "Radio2", Vector3(.85, 1.74, .1))
	_stock(electronics, PHONE, "Phone", Vector3(-.45, 2.52, 0))
	_stock(electronics, CLOCK, "Clock", Vector3(.65, 2.52, .08))
	_stock(electronics, CASE, "Luggage", Vector3(-.55, .18, 0))
	_stock(electronics, BOX, "SpareParts", Vector3(.55, .18, 0))
	_tags(electronics, "$45   /   $60", .83)
	_tags(electronics, "TESTED - ASK RUSTY", 1.61)
	var household := _prop(SHELF, "Household", Vector3(-15.5, 0, 26.4), PI / 2)
	_stock(household, RADIO, "Radio", Vector3(-.6, .96, .08))
	_stock(household, CLOCK, "Clock", Vector3(.55, .96, .08))
	_stock(household, LAMP, "Lamp", Vector3(-.6, 1.74, 0))
	_stock(household, PHONE, "Phone", Vector3(.55, 1.74, .04))
	_stock(household, BOX, "Box1", Vector3(-.6, .18, 0))
	_stock(household, BOX, "Box2", Vector3(.55, .18, 0))
	_stock(household, CASE, "Case", Vector3(0, 2.52, 0))
	_tags(household, "BARGAINS FROM $5", .83)
	var odds := _prop(SHELF, "Oddities", Vector3(-2.5, 0, 23.4), -PI / 2)
	_stock(odds, PHONE, "Phone", Vector3(-.7, .96, 0))
	_stock(odds, RADIO, "Radio", Vector3(0, .96, .08))
	_stock(odds, CLOCK, "Clock", Vector3(.7, .96, .08))
	_stock(odds, TV, "TV", Vector3(-.55, 1.74, 0))
	_stock(odds, LAMP, "Lamp", Vector3(.6, 1.74, 0))
	_stock(odds, BOX, "Box", Vector3(-.6, .18, 0))
	_stock(odds, CASE, "Case", Vector3(.55, .18, 0))
	_tags(odds, "SECOND CHANCE GOODS", .83)
	var table := _prop(TABLE, "UsedTable", Vector3(-4.7, 0, 24.5))
	_stock(table, TV, "PortableTV", Vector3(0, .463, 0))
	_prop(CHAIR, "UsedArmchair", Vector3(-4.7, 0, 25.7), PI)
	_sign("FurnitureTag", "TAKE THE SET $80", Vector3(-4.7, .25, 24.78), 0, .045)
	_prop(TRUNK, "Trunk", Vector3(-14.1, 0, 28.6), .15)
	_prop(FAN, "UsedFan", Vector3(-14, 0, 24), PI / 3)
	_prop(ART, "Picture", Vector3(-15.83, 3.55, 26.4), PI / 2)
	_sign("ElectronicsSign", "TVS / RADIOS", Vector3(-15.82, 3.1, 23), PI / 2, .15)
	_sign("GoodsSign", "ODDS & ENDS", Vector3(-2.18, 3.1, 23.4), -PI / 2, .15)
	_sign("LoansSign", "CASH LOANS\nBUY - SELL - TRADE", Vector3(-15.82, 3.7, 23), PI / 2, .17)
	_sign("CounterSign", "NO REFUNDS\nALL SALES FINAL", Vector3(-15.82, 3.35, 28.3), PI / 2, .09)
	_sign("GoldWindow", "CASH\nFOR GOLD", Vector3(-14.6, 1.85, 29.87), PI, .16)
	var open := _sign("Open", "OPEN", Vector3(-5.1, 2.05, 29.87), PI, .14)
	open.style = SignBoard.Style.NEON
	open.neon_color = Color(.8, .18, .08)
	var frontage := _sign(
		"ExteriorSign", "RUSTY HOGG'S\nPAWN & GUN", Vector3(-9, 3.5, 30.12), 0, .38
	)
	frontage.style = SignBoard.Style.NEON
	frontage.neon_color = Color(.85, .42, .12)
	_pawn_balls()
	_window_bars()
	for at: Vector3 in [Vector3(-12, 4.95, 23), Vector3(-5, 4.95, 25)]:
		var light := _prop(FIXTURE, "Fluorescent%d" % _root.get_child_count(), at)
		light.rotation.x = PI
	var packed := PackedScene.new()
	assert(packed.pack(_root) == OK)
	assert(ResourceSaver.save(packed, "res://features/pawn_shop/dressing.tscn") == OK)
	_root.free()
	quit()


func _prop(scene: PackedScene, id: String, at: Vector3, yaw: float = 0) -> Node3D:
	var prop := scene.instantiate() as Node3D
	prop.name = id
	prop.position = at
	prop.rotation.y = yaw
	_root.add_child(prop)
	prop.owner = _root
	return prop


func _stock(parent: Node3D, scene: PackedScene, id: String, at: Vector3) -> void:
	var prop := scene.instantiate() as Node3D
	prop.name = id
	prop.position = at
	parent.add_child(prop)
	prop.owner = _root


func _sign(id: String, text: String, at: Vector3, yaw: float, height: float) -> SignBoard:
	var sign := _prop(SIGN, id, at, yaw) as SignBoard
	sign.text = text
	sign.letter_height = height
	sign.padding = .04
	return sign


func _tags(shelf: Node3D, text: String, y: float) -> void:
	var sign := SIGN.instantiate() as SignBoard
	sign.name = "Price%d" % int(y * 100)
	sign.text = text
	sign.letter_height = .045
	sign.padding = .015
	sign.position = Vector3(0, y, .285)
	shelf.add_child(sign)
	sign.owner = _root


func _pawn_balls() -> void:
	# Reuse the existing pawn counter's low-poly sphere/post construction at shop scale.
	var ball := SphereMesh.new()
	ball.radius = .2
	ball.height = .4
	ball.radial_segments = 12
	ball.rings = 6
	ball.material = BRASS
	for index: int in 3:
		var drop := .55 if index == 1 else .35
		var x := -12.5 + (index - 1) * .5
		var sphere := MeshInstance3D.new()
		sphere.name = "PawnBall%d" % index
		sphere.mesh = ball
		sphere.position = Vector3(x, 3.55 - drop, 24.5)
		_root.add_child(sphere)
		sphere.owner = _root
		_bar(
			"Hanger%d" % index,
			Vector3(.025, drop - .18, .025),
			Vector3(x, 3.55 - (drop - .18) * .5, 24.5)
		)
	_bar("PawnCrossbar", Vector3(1.05, .04, .04), Vector3(-12.5, 3.55, 24.5))
	_bar("CeilingRod", Vector3(.03, 1.43, .03), Vector3(-12.5, 4.285, 24.5))


func _bar(id: String, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = BRASS
	var model := MeshInstance3D.new()
	model.name = id
	model.mesh = mesh
	model.position = at
	_root.add_child(model)
	model.owner = _root


func _window_bars() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.015, 2, .02)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.16, .18, .17)
	mesh.material = material
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 33:
		surface.append_from(
			mesh, 0, Transform3D(Basis.IDENTITY, Vector3(-15.76 + index * .36, 1.5, 29.9))
		)
	var bars := MeshInstance3D.new()
	bars.name = "WindowSecurityBars"
	bars.mesh = surface.commit()
	bars.material_override = material
	bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(bars)
	bars.owner = _root
