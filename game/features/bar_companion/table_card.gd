extends Node3D
## Two-sided tabletop number card. Uses the signage kit's exact glyph UVs/atlas.

static var _paper: StandardMaterial3D
static var _ink: StandardMaterial3D

@export var number := 1


func _ready() -> void:
	if _paper == null:
		_paper = StandardMaterial3D.new()
		_paper.albedo_color = Color("ead6a4")
		_paper.roughness = 0.9
		_ink = StandardMaterial3D.new()
		_ink.albedo_color = Color("391e20")
		_ink.albedo_texture = SignLetterAtlas.texture()
		_ink.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_ink.alpha_scissor_threshold = 0.5
	_box("Foot", Vector3(0.30, 0.025, 0.16), Vector3(0, 0.0125, 0))
	_box("Card", Vector3(0.26, 0.30, 0.018), Vector3(0, 0.175, 0))
	for side: int in 2:
		var letters := MeshInstance3D.new()
		letters.name = "NumberFront" if side == 0 else "NumberBack"
		letters.mesh = SignBoard.letters_mesh(str(number), 0.22, 0.010)
		letters.material_override = _ink
		letters.position.y = 0.175
		letters.rotation.y = PI * side
		letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(letters)


func _box(label: String, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = _paper
	part.position = at
	add_child(part)
