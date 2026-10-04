@tool
class_name SignBoard
extends Node3D
## Modeled sign: backing board, frame and mount, with letters built as quads on one
## mesh from the shared SignLetterAtlas (no Label3D). The readable face looks along
## +Z, like Label3D, so a sign can replace a label at the same transform.
##
## FLUSH: the board's back sits on the wall plane z = 0.
## BRACKET: a blade sign on an arm projecting along +Z from a wall at z = 0; the
##   text faces ±X so passers-by in the corridor read it.
## HANGING: rods rise to the ceiling attachment point at y = 0; two-sided.

enum Style { BRASS, NEON }
enum Mount { FLUSH, BRACKET, HANGING }

const GLYPH_ADVANCE := 6
const LINE_ADVANCE := 9
const BOARD_DEPTH := 0.04
const FRAME_WIDTH := 0.03
const FRAME_RELIEF := 0.012
const LETTER_LIFT := 0.003
const ROD_LENGTH := 0.35
const ARM_GAP := 0.08

static var _materials := {}

@export_multiline var text := "SIGN":
	set(value):
		text = value
		_queue_rebuild()
@export_range(0.02, 1.0, 0.01, "suffix:m") var letter_height := 0.14:
	set(value):
		letter_height = value
		_queue_rebuild()
@export_range(0.0, 0.5, 0.01, "suffix:m") var padding := 0.06:
	set(value):
		padding = value
		_queue_rebuild()
@export var style := Style.BRASS:
	set(value):
		style = value
		_queue_rebuild()
@export var mount := Mount.FLUSH:
	set(value):
		mount = value
		_queue_rebuild()
@export var two_sided := false:
	set(value):
		two_sided = value
		_queue_rebuild()
@export var neon_color := Color(1.0, 0.25, 0.55):
	set(value):
		neon_color = value
		_queue_rebuild()

var _pending := false


func _ready() -> void:
	rebuild()


## Board size (width, height) in metres for the current text and letter height.
func board_size() -> Vector2:
	return measure(text, letter_height, padding)


static func measure(value: String, cap_height: float, pad: float) -> Vector2:
	var lines := value.split("\n")
	var columns := 0
	for line in lines:
		columns = maxi(columns, line.length())
	var px := cap_height / SignLetterAtlas.GLYPH_H
	var width := maxf(columns * GLYPH_ADVANCE - 1, 1) * px + pad * 2.0
	var height := (lines.size() * LINE_ADVANCE - 2) * px + pad * 2.0
	return Vector2(width, height)


func rebuild() -> void:
	_pending = false
	for child in get_children():
		if child.has_meta("sign_part"):
			remove_child(child)
			child.free()
	var size := board_size()
	var board := _part(Node3D.new(), "Board")
	add_child(board)
	match mount:
		Mount.FLUSH:
			board.position = Vector3(0, 0, BOARD_DEPTH * 0.5)
		Mount.HANGING:
			board.position = Vector3(0, -ROD_LENGTH - size.y * 0.5, 0)
			for side: float in [-1.0, 1.0]:
				_box(
					"Rod%d" % int(side > 0),
					Vector3(0.012, ROD_LENGTH, 0.012),
					Vector3(side * size.x * 0.4, -ROD_LENGTH * 0.5, 0),
					"metal"
				)
		Mount.BRACKET:
			var arm_length := size.x + ARM_GAP + FRAME_WIDTH
			_box("WallPlate", Vector3(0.12, 0.16, 0.02), Vector3(0, -0.08, 0.01), "metal")
			_box(
				"Arm",
				Vector3(0.025, 0.025, arm_length),
				Vector3(0, -0.0125, arm_length * 0.5),
				"metal"
			)
			board.position = Vector3(0, -0.06 - size.y * 0.5, ARM_GAP + size.x * 0.5)
			board.rotation.y = PI * 0.5
			for offset: float in [-0.4, 0.4]:
				_box(
					"Hanger%d" % int(offset > 0),
					Vector3(0.008, 0.06, 0.008),
					Vector3(0, -0.03, board.position.z + offset * size.x),
					"metal"
				)
	_build_board(board, size)


func _build_board(board: Node3D, size: Vector2) -> void:
	_box("Backing", Vector3(size.x, size.y, BOARD_DEPTH), Vector3.ZERO, "backing", board)
	# Flush frames stand proud of the face only, so nothing pokes into the wall.
	var sides := 1.0 if mount == Mount.FLUSH and not two_sided else 2.0
	var bar_depth := BOARD_DEPTH + FRAME_RELIEF * sides
	var bar_z := FRAME_RELIEF * 0.5 if mount == Mount.FLUSH else 0.0
	var half := size * 0.5
	var rail := Vector3(size.x + FRAME_WIDTH * 2.0, FRAME_WIDTH, bar_depth)
	var stile := Vector3(FRAME_WIDTH, size.y, bar_depth)
	var frame_builder := SurfaceTool.new()
	frame_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in [
		[rail, Vector3(0, half.y + FRAME_WIDTH * .5, bar_z)],
		[rail, Vector3(0, -half.y - FRAME_WIDTH * .5, bar_z)],
		[stile, Vector3(-half.x - FRAME_WIDTH * .5, 0, bar_z)],
		[stile, Vector3(half.x + FRAME_WIDTH * .5, 0, bar_z)]
	]:
		var box := BoxMesh.new()
		box.size = part[0]
		frame_builder.append_from(box, 0, Transform3D(Basis.IDENTITY, part[1]))
	var frame := MeshInstance3D.new()
	frame.mesh = frame_builder.commit()
	frame.material_override = _material("frame")
	board.add_child(_part(frame, "Frame"))
	var front := MeshInstance3D.new()
	front.name = "Letters"
	front.mesh = letters_mesh(text, letter_height, BOARD_DEPTH * 0.5 + LETTER_LIFT)
	front.material_override = _material("letters")
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(_part(front, "Letters"))
	if mount != Mount.FLUSH or two_sided:
		var back := front.duplicate() as MeshInstance3D
		back.rotation.y = PI
		board.add_child(_part(back, "LettersBack"))


## One mesh of glyph quads centred on the origin, facing +Z at depth z.
static func letters_mesh(value: String, cap_height: float, z: float) -> ArrayMesh:
	var px := cap_height / SignLetterAtlas.GLYPH_H
	var lines := value.split("\n")
	var block_h := (lines.size() * LINE_ADVANCE - 2) * px
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for row in lines.size():
		var line := lines[row]
		var line_w := maxf(line.length() * GLYPH_ADVANCE - 1, 0) * px
		var top := block_h * 0.5 - row * LINE_ADVANCE * px
		for i in line.length():
			if line[i] == " ":
				continue
			var left := -line_w * 0.5 + i * GLYPH_ADVANCE * px
			var right := left + SignLetterAtlas.GLYPH_W * px
			var bottom := top - SignLetterAtlas.GLYPH_H * px
			var uv := SignLetterAtlas.uv_rect(line[i])
			var corners := [
				[Vector3(left, top, z), uv.position],
				[Vector3(left, bottom, z), Vector2(uv.position.x, uv.end.y)],
				[Vector3(right, bottom, z), uv.end],
				[Vector3(right, top, z), Vector2(uv.end.x, uv.position.y)],
			]
			for k: int in [0, 2, 1, 0, 3, 2]:
				verts.append(corners[k][0])
				uvs.append(corners[k][1])
				normals.append(Vector3.BACK)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _box(
	part_name: String, size: Vector3, at: Vector3, kind: String, parent: Node3D = self
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(kind)
	parent.add_child(_part(instance, part_name))
	return instance


func _part(node: Node3D, part_name: String) -> Node3D:
	node.name = part_name
	node.set_meta("sign_part", true)
	return node


func _material(kind: String) -> StandardMaterial3D:
	var neon := style == Style.NEON
	var key := "%s/%s/%s" % [kind, neon, neon_color.to_html() if neon else ""]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	match kind:
		"backing":
			mat.albedo_color = Color(0.05, 0.05, 0.07) if neon else Color(0.16, 0.05, 0.06)
			mat.roughness = 0.8
		"frame", "metal":
			mat.albedo_color = Color(0.12, 0.12, 0.14) if neon else Color(0.78, 0.58, 0.24)
			mat.metallic = 0.0 if neon else 0.8
			mat.roughness = 0.4
		"letters":
			mat.albedo_texture = SignLetterAtlas.texture()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.5
			mat.albedo_color = neon_color if neon else Color(0.98, 0.84, 0.45)
			mat.emission_enabled = true
			mat.emission = neon_color if neon else Color(0.45, 0.33, 0.12)
			mat.emission_energy_multiplier = 2.0 if neon else 0.6
	_materials[key] = mat
	return mat


func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	rebuild.call_deferred()
