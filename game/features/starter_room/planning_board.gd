@tool
extends Node3D
## Static, non-interactive planning art. Face +Z; built only when the room is loaded.

const PAPER := preload("res://assets/starter_room/planning_paper.png")
const STEEL := preload("res://features/procedural_rooms/materials/garage_rail.tres")
const SIZE := Vector2(2.8, 2.1)
const RED := Color("9e302b")
const INK := Color("303b3d")
const WHITE := Color("d7e7dd")
@export var blueprint := false
var _lines: SurfaceTool
var _marks: SurfaceTool
var _letters: SurfaceTool
var _annotations: SurfaceTool


func _ready() -> void:
	var backing := BoxMesh.new()
	backing.size = Vector3(SIZE.x + .08, SIZE.y + .08, .04)
	_add("Backing", backing, STEEL, Vector3(0, 0, .02))
	var paper := QuadMesh.new()
	paper.size = SIZE
	var mesh := ArrayMesh.new()
	var arrays := paper.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i: int in uvs.size():
		uvs[i] = Vector2((.52 if blueprint else .02) + uvs[i].x * .46, .02 + uvs[i].y * .96)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := _material(Color.WHITE)
	material.albedo_texture = PAPER
	_add("Paper", mesh, material, Vector3(0, 0, .042))
	_lines = _tool()
	_marks = _tool()
	_letters = _tool()
	_annotations = _tool()
	if blueprint:
		_casino()
	else:
		_world()
	for data: Array in [
		["Diagram", _lines, WHITE if blueprint else INK, false],
		["Markup", _marks, RED, false],
		["Lettering", _letters, WHITE if blueprint else INK, true],
		["Annotations", _annotations, RED, true]
	]:
		var tool: SurfaceTool = data[1]
		tool.index()
		var mat := _material(data[2])
		if data[3]:
			mat.albedo_texture = SignLetterAtlas.texture()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_add(data[0], tool.commit(), mat)


func _world() -> void:
	_text("WORLD / ROUTE MAP", Vector2(0, .87), .13)
	_text("THE GOLDEN CROWN", Vector2(-.61, .45), .075)
	_rect(Rect2(-1.18, .22, 1.14, .46))
	_rect(Rect2(.16, .22, 1.04, .46))
	_text("STREET\nDISTRICT", Vector2(.68, .45), .085)
	_rect(Rect2(.16, -.56, 1.04, .46))
	_text("BASEMENT\nGARAGE B1-B5", Vector2(.68, -.33), .075)
	_rect(Rect2(-1.18, -.53, 1.14, .40))
	_text("OPERATIONS\nGARAGE", Vector2(-.61, -.33), .085)
	# Schematics mirror the van's three routes, not physical world coordinates.
	for pair: Array in [
		[Vector2(-.61, -.13), Vector2(-.61, .22)],
		[Vector2(-.04, -.27), Vector2(.16, .4)],
		[Vector2(-.04, -.4), Vector2(.16, -.4)],
	]:
		_arrow(pair[0], pair[1])
	_ring(Vector2(-.61, -.33), Vector2(.65, .30))
	_line(Vector2(-.61, -.63), Vector2(-.61, -.70), _marks)
	_text("YOU ARE HERE", Vector2(-.61, -.77), .10, true)
	_text("SCHEMATIC - NOT TO SCALE", Vector2(.2, -.96), .065)
	_text("ROUTES / VAN", Vector2(.67, -.72), .075, true)
	# Hand-marked cross and registration ticks give the map its planning-board tone.
	_line(Vector2(-1.28, .73), Vector2(-1.18, .63), _marks)
	_line(Vector2(-1.18, .73), Vector2(-1.28, .63), _marks)


func _casino() -> void:
	_text("GOLDEN CROWN / BLUEPRINTS", Vector2(0, .88), .115)
	# Ground plan in authored metres: hall x +/-24, z +/-20; pit 30 x 24.
	var scale := .031
	_rect(Rect2(-24 * scale, -20 * scale, 48 * scale, 40 * scale))
	_rect(Rect2(-15 * scale, -12 * scale, 30 * scale, 24 * scale))
	_rect(Rect2(-32 * scale, -12 * scale, 8 * scale, 26 * scale))
	for y: float in [-9 * scale, 9 * scale]:
		_rect(Rect2(-3 * scale, y - 3 * scale, 6 * scale, 6 * scale))
	_text("GAMING\nPIT", Vector2.ZERO, .075)
	_text("BAR", Vector2(-.85, .04), .06)
	_text("N", Vector2(.98, .57), .085)
	_arrow(Vector2(.98, .35), Vector2(.98, .49), false)
	_text("ELEVATOR", Vector2(0, .71), .065)
	_text("LOBBY", Vector2(0, -.73), .065)
	# Red plan annotations are scenery, not a new casino mission or access route.
	_ring(Vector2(0, .64), Vector2(.21, .10))
	_arrow(Vector2(-1.15, .48), Vector2(-.19, .63))
	_text("ENTRY?", Vector2(-1, .57), .075, true)
	_text("UPPER BAR / SECTION", Vector2(.80, -.78), .065)
	for y: float in [-.96, -.86]:
		_line(Vector2(.35, y), Vector2(1.23, y), _lines)
	_line(Vector2(.38, -.96), Vector2(.38, -.86), _lines)
	_line(Vector2(1.20, -.96), Vector2(1.20, -.86), _lines)
	_text("5M", Vector2(.80, -.91), .055)
	_text("GROUND PLAN / STUDY COPY", Vector2(-.47, -.95), .06)


func _text(value: String, at: Vector2, height: float, annotation := false) -> void:
	var mesh := SignBoard.letters_mesh(value, height, .049)
	(_annotations if annotation else _letters).append_from(
		mesh, 0, Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0))
	)
	set_meta("text_" + str(get_meta_list().size()), value)


func _rect(rect: Rect2) -> void:
	var a := rect.position
	var b := rect.end
	for pair: Array in [
		[a, Vector2(b.x, a.y)],
		[Vector2(b.x, a.y), b],
		[b, Vector2(a.x, b.y)],
		[Vector2(a.x, b.y), a]
	]:
		_line(pair[0], pair[1], _lines)


func _arrow(a: Vector2, b: Vector2, red := true) -> void:
	var tool := _marks if red else _lines
	_line(a, b, tool)
	var direction := (b - a).normalized()
	var side := Vector2(-direction.y, direction.x) * .055
	_line(b, b - direction * .1 + side, tool)
	_line(b, b - direction * .1 - side, tool)


func _ring(at: Vector2, radius: Vector2) -> void:
	for i: int in 24:
		var a := TAU * i / 24
		var b := TAU * (i + 1) / 24
		_line(at + Vector2(cos(a), sin(a)) * radius, at + Vector2(cos(b), sin(b)) * radius, _marks)


func _line(a: Vector2, b: Vector2, tool: SurfaceTool) -> void:
	var normal := Vector2(-(b - a).y, (b - a).x).normalized() * .008
	var points := [a - normal, a + normal, b + normal, b - normal]
	for i: int in [0, 1, 2, 0, 2, 3]:
		tool.set_normal(Vector3.BACK)
		tool.set_uv(Vector2.ZERO)
		tool.add_vertex(Vector3(points[i].x, points[i].y, .047))


func _tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return material


func _add(title: String, mesh: Mesh, material: Material, at := Vector3.ZERO) -> void:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
