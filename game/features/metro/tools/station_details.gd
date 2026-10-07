extends RefCounted
## Shared low-poly ironwork and four station identities, using existing small atlases.

const ROOT := "res://features/metro/"
const ACCENTS: Array[Color] = [Color("927344"), Color("934e3b"), Color("547783"), Color("507965")]
const SLOGANS: Array[String] = [
	"THE GOLDEN CROWN\nOPEN ALL NIGHT",
	"MARKET STREET\nSPACE TO LET",
	"WORKS / SERVICE LINE\nAUTHORIZED PERSONNEL ONLY",
	"RESIDENCES\nPLEASE KEEP IT DOWN"
]


static func elevator(builder: Node, cab: Node3D) -> void:
	var green: ShaderMaterial = builder._surface(
		"res://assets/street_props/surfaces/painted_concrete.png", Color("4c9763"), 1.5
	)
	var steel: ShaderMaterial = builder._surface(
		"res://assets/street_props/surfaces/painted_concrete.png", Color("bbc1b8"), 1.0
	)
	(cab.get_node("Car/Doors/Frame") as MeshInstance3D).material_override = green
	for side: String in ["LeftLeaf", "RightLeaf"]:
		(cab.get_node("Car/Doors/" + side + "/Visual") as MeshInstance3D).material_override = steel
	# Two cast-iron entrance posts with the classic green/white globes. Keep the
	# existing 3.2 m footprint and 2.55 m room headroom so every connector still fits.
	var iron := SurfaceTool.new()
	var glass := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-1.53, 1.53]:
		var post := CylinderMesh.new()
		post.top_radius = 0.065
		post.bottom_radius = 0.085
		post.height = 1.93
		post.radial_segments = 8
		post.rings = 1
		iron.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(x, 0.965, 0.03)))
		for part: Array in [
			[Vector3(0.25, 0.12, 0.25), Vector3(x, 0.06, 0.03)],
			[Vector3(0.2, 0.09, 0.2), Vector3(x, 1.91, 0.03)]
		]:
			var base := BoxMesh.new()
			base.size = part[0]
			iron.append_from(base, 0, Transform3D(Basis.IDENTITY, part[1]))
		var globe := SphereMesh.new()
		globe.radius = 0.18
		globe.height = 0.18
		globe.is_hemisphere = true
		globe.radial_segments = 12
		globe.rings = 4
		iron.append_from(globe, 0, Transform3D(Basis.IDENTITY, Vector3(x, 2.16, 0.03)))
		glass.append_from(globe, 0, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, 2.16, 0.03)))
	_mesh(cab, "GreenEntrancePosts", iron.commit(), green)
	_mesh(cab, "EntranceGlobes", glass.commit(), builder._flat(Color("c8d6b0"), 0.4))
	var sign := cab.get_node("Car/Sign") as SignBoard
	sign.style = SignBoard.Style.NEON
	sign.neon_color = Color("c7d1be")
	var light := cab.get_node("Car/CabLight") as OmniLight3D
	light.light_color = Color("c6d4b5")
	# A separate station-only GridMap shaft meets the ceiling; room-side elevators
	# keep their established clearance in rooms with lower ceilings.
	var old: MeshLibrary = builder.library
	builder.library = MeshLibrary.new()
	builder.set("_id", 0)
	var shaft_id: int = builder.tile(Vector3(3.2, 1.8, 3.2), Vector3(0, 3.4, -1.6), steel)
	var collar_id: int = builder.tile(
		Vector3(3.35, 0.13, 3.3), Vector3(0, 4.22, -1.6), green, false
	)
	ResourceSaver.save(builder.library, ROOT + "shaft_tiles.tres")
	(builder.library as MeshLibrary).take_over_path(ROOT + "shaft_tiles.tres")
	var shaft := Node3D.new()
	var shell: GridMap = builder.grid(shaft, "Shaft")
	shell.set_cell_item(Vector3i.ZERO, shaft_id)
	var collar: GridMap = builder.grid(shaft, "CeilingCollar")
	collar.set_cell_item(Vector3i.ZERO, collar_id)
	builder.save(shaft, ROOT + "access_shaft.tscn")
	shaft.free()
	builder.library = old


static func station(builder: Node, room: Node3D, board_id: int) -> void:
	# Duplicate only the board panels/labels, not the full platform presentation.
	var panels: GridMap = builder.grid(room, "ReverseDepartureBoards")
	for z: int in [-48, -24, 0, 24, 48]:
		panels.set_cell_item(Vector3i(7, 0, z), board_id)
		for side: int in [-1, 1]:
			var board := Label3D.new()
			board.name = "BoardReverse%d_%d" % [z, side]
			board.position = Vector3(11.5, 4.4, z + side * 0.07)
			board.rotation.y = PI if side == -1 else 0.0
			board.double_sided = false
			board.font_size = 48
			board.pixel_size = 0.008
			board.modulate = Color("c4d2c9")
			room.add_child(board)
	var identity := Node3D.new()
	identity.name = "Identity"
	room.add_child(identity)
	var original: MeshLibrary = builder.library
	for index: int in 4:
		builder.library = MeshLibrary.new()
		builder.set("_id", 0)
		var style := Node3D.new()
		style.name = "Station%d" % index
		style.visible = index == 0
		identity.add_child(style)
		var paint: ShaderMaterial = builder._surface(
			"res://assets/street_props/surfaces/peeling_plaster.png", ACCENTS[index], 0.75
		)
		var trim: int = builder.tile(Vector3(0.08, 0.75, 2), Vector3(0.18, 4.0, 0), paint, false)
		var reverse_trim: int = builder.tile(
			Vector3(0.08, 0.75, 2), Vector3(-0.18, 4.0, 0), paint, false
		)
		var band: GridMap = builder.grid(style, "StationBand")
		for z: int in range(-66, 67, 2):
			band.set_cell_item(Vector3i(-4, 0, z), trim)
			band.set_cell_item(Vector3i(20, 0, z), reverse_trim)
		var beam: int = builder.tile(Vector3(24, 0.14, 0.32), Vector3(8, 5.21, 0), paint, false)
		var beams: GridMap = builder.grid(style, "BeamTrim")
		for z: int in range(-60, 61, 12):
			beams.set_cell_item(Vector3i(0, 0, z), beam)
		# The opposite lining faces inward too.
		for z: int in [-54, -18, 18, 54]:
			for x: float in [-3.75, 19.75]:
				builder.add_sign(
					style,
					MetroRules.NAMES[index],
					Vector3(x, 4.0, z),
					PI / 2 if x < 0 else -PI / 2,
					0.27
				)
		for z: int in [-36, 36]:
			builder.add_sign(style, SLOGANS[index], Vector3(-3.73, 2.2, z), PI / 2, 0.14)
		_dressing(builder, style, index)
		var path := ROOT + "identity_%d.tres" % index
		ResourceSaver.save(builder.library, path)
		(builder.library as MeshLibrary).take_over_path(path)
	builder.library = original


static func _dressing(builder: Node, style: Node3D, index: int) -> void:
	var rust: ShaderMaterial = builder._surface(
		"res://assets/street_props/surfaces/rusted_steel.png", Color("6e6550"), 1.0
	)
	var details: GridMap = builder.grid(style, "Details")
	if index == 0:
		# Crown: faded cream lining with old brass-coloured vertical pilasters.
		var material: ShaderMaterial = builder._surface(
			"res://assets/street_props/surfaces/painted_concrete.png", Color("c1b89b"), 0.5
		)
		var tile: int = builder.tile(Vector3(0.16, 3.6, 1.4), Vector3(0, 2.0, 0), material, false)
		for z: int in range(-60, 61, 8):
			for x: int in [-3, 19]:
				details.set_cell_item(Vector3i(x, 0, z), tile)
	elif index == 1:
		# Market: exposed brick patches and more old spray paint.
		var material: ShaderMaterial = builder._surface(
			"res://assets/street_props/surfaces/brick_wall.png", Color("b59378"), 0.65
		)
		var tile: int = builder.tile(Vector3(0.1, 2.2, 4), Vector3(0, 1.8, 0), material, false)
		for z: int in [-58, -34, -10, 14, 38, 58]:
			details.set_cell_item(Vector3i(-3, 0, z), tile)
			var tag: int = builder._graffiti(posmod(z, 8), 2.7)
			details.set_cell_item(Vector3i(19, 0, z), tag)
	elif index == 2:
		# Works: low utility ducts and rusty service panels, clear of the walkway.
		var duct: int = builder.tile(Vector3(0.6, 0.25, 4), Vector3(0, 5.33, 0), rust, false)
		for z: int in range(-64, 65, 4):
			for x: int in [5, 12]:
				details.set_cell_item(Vector3i(x, 0, z), duct)
		var panel: int = builder.tile(Vector3(0.2, 2.0, 2.6), Vector3(0, 2.0, 0), rust, false)
		for z: int in [-50, -26, 26, 50]:
			details.set_cell_item(Vector3i(19, 0, z), panel)
	else:
		# Residences: peeling sea-green lower walls and old cream inset panels.
		var plaster: ShaderMaterial = builder._surface(
			"res://assets/street_props/surfaces/peeling_plaster.png", Color("a5b99c"), 0.5
		)
		var panel: int = builder.tile(Vector3(0.12, 2.0, 3.2), Vector3(0, 1.8, 0), plaster, false)
		for z: int in range(-60, 61, 6):
			for x: int in [-3, 19]:
				details.set_cell_item(Vector3i(x, 0, z), panel)


static func _mesh(parent: Node3D, label: String, mesh: ArrayMesh, material: Material) -> void:
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	parent.add_child(node)
