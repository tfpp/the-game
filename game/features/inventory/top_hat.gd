class_name TopHat
extends Node3D
## A tall black silk top hat built from low-poly primitives. The origin is the
## underside of the brim, centered, so parents place it straight onto a head top.
## Used by the worn hat (`BlockPlayerModel`) and its world/shop view (`ClothingModel`).

const HEIGHT := 0.30
const BRIM_RADIUS := 0.20
const CROWN_RADIUS := 0.13
const SILK := Color("141418")

var band_color := ClothingCatalog.COLORS[1]


func _ready() -> void:
	var silk := StandardMaterial3D.new()
	silk.albedo_color = SILK
	silk.roughness = 0.45
	silk.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var band := StandardMaterial3D.new()
	band.albedo_color = band_color.darkened(0.25)
	band.roughness = 0.8
	band.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_cylinder("Brim", 0.012, BRIM_RADIUS, BRIM_RADIUS, 0.025, silk)
	# Slightly flared crown, the way a proper stovepipe widens toward the top.
	_cylinder("Crown", 0.025 + HEIGHT * 0.5, CROWN_RADIUS + 0.01, CROWN_RADIUS, HEIGHT, silk)
	_cylinder("Band", 0.025 + 0.035, CROWN_RADIUS + 0.004, CROWN_RADIUS + 0.004, 0.06, band)


func _cylinder(
	label: String, y: float, top: float, bottom: float, height: float, material: Material
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position.y = y
	add_child(part)
