extends Node3D
## Shared physical finishes for imported props, also used by the level geometry.

const FINISHES: Dictionary[String, Material] = {
	"Walnut": preload("res://features/casino_hub/materials/wood.tres"),
	"Brass": preload("res://features/casino_hub/materials/brass.tres"),
	"Chrome": preload("res://features/casino_hub/materials/chrome.tres"),
	"Enamel": preload("res://features/casino_hub/materials/teal.tres"),
	"Velvet": preload("res://features/casino_hub/materials/velvet.tres"),
	"Ivory": preload("res://features/casino_hub/materials/opal.tres"),
}


func _ready() -> void:
	apply_finishes(self)


static func apply_finishes(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and FINISHES.has(str(mesh.name)):
		mesh.material_override = FINISHES[str(mesh.name)]
	for child: Node in node.get_children():
		apply_finishes(child)
