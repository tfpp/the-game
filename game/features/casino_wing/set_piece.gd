extends Node3D
## Reusable casino furnishings: local floor-centred bounds, shared existing artwork.

const KIT := preload("res://features/procedural_rooms/example_kit.gd")
const FINISH := preload("res://features/casino_hub/model_materials.gd")
const SLOT := preload("res://features/casino_hub/models/slot_cabinet.tscn")
const BENCH := preload("res://features/casino_hub/models/lounge_bench.tscn")
const PLANT := preload("res://features/casino_hub/models/ceramic_planter.tscn")
const TABLE := preload("res://assets/casino_hub/models/salon_card_table.glb")
const BAR := preload("res://assets/casino_hub/models/salon_bar.glb")
const STOOL := preload("res://features/casino_hub/models/casino_stool.tscn")
const WOOD := preload("res://features/casino_hub/materials/wood.tres")
const BRASS := preload("res://features/casino_hub/materials/brass.tres")
const STEEL := preload("res://features/casino_hub/materials/chrome.tres")
const DARK := preload("res://features/casino_hub/materials/teal.tres")
@export var kind := "lounge"


func _ready() -> void:
	match kind:
		"slot_bank":
			for x: float in [-1.3, 0, 1.3]:
				_prop(SLOT, Vector3(x, 0, 0), Vector3(1.1, 2, 1), PI)
		"cards":
			_prop(TABLE, Vector3.ZERO, Vector3(3.4, 1.1, 2.5), 0)
			for x: float in [-1.3, 0, 1.3]:
				_prop(STOOL, Vector3(x, 0, 1.8), Vector3(.65, .8, .65), 0)
		"bar":
			_prop(BAR, Vector3.ZERO, Vector3(5, 2.7, 1.7), 0)
			for x: float in [-1.7, 0, 1.7]:
				_prop(STOOL, Vector3(x, 0, 1.4), Vector3(.65, .8, .65), 0)
		"lounge":
			_prop(BENCH, Vector3(0, 0, -.5), Vector3(3, 1.2, 1), 0)
			_prop(PLANT, Vector3(1.8, 0, -.5), Vector3(.7, 1.6, .7), 0)
			KIT.box(self, "CoffeeTable", Vector3(2, .45, .6), Vector3(0, .225, .7), WOOD)
		"office", "security", "counting":
			KIT.box(self, "Desk", Vector3(2.8, .9, 1.2), Vector3(0, .45, 0), WOOD)
			_prop(STOOL, Vector3(0, 0, 1.1), Vector3(.65, .8, .65), 0)
			if kind == "security":
				for x: float in [-.75, .75]:
					KIT.box(
						self, "Monitor%s" % x, Vector3(.6, .45, .15), Vector3(x, 1.18, -.35), STEEL
					)
			else:
				_gold(Vector3(0, .94, 0))
		"vault_safes":
			for x: float in [-1.25, 0, 1.25]:
				for y: float in [.55, 1.65]:
					KIT.box(
						self, "Safe%s_%s" % [x, y], Vector3(1.15, 1, .65), Vector3(x, y, 0), STEEL
					)
					KIT.box(
						self,
						"SafeDoor%s_%s" % [x, y],
						Vector3(1, .85, .02),
						Vector3(x, y, -.34),
						DARK,
						false
					)
					KIT.box(
						self,
						"Handle%s_%s" % [x, y],
						Vector3(.3, .06, .08),
						Vector3(x, y, -.37),
						BRASS,
						false
					)
		"gold_rack":
			for y: float in [.6, 1.3]:
				KIT.box(self, "Shelf%s" % y, Vector3(3.4, .1, 1), Vector3(0, y, 0), STEEL)
				_gold(Vector3(0, y + .07, 0))
			for x: float in [-1.6, 1.6]:
				KIT.box(self, "Leg%s" % x, Vector3(.1, 1.5, 1), Vector3(x, .75, 0), STEEL)


func _gold(at: Vector3) -> void:
	for x: float in [-.6, 0, .6]:
		for z: float in [-.2, .2]:
			KIT.box(
				self,
				"Bar%s_%s_%s" % [at.y, x, z],
				Vector3(.45, .12, .24),
				at + Vector3(x, .06, z),
				BRASS,
				false
			)


func _prop(scene: PackedScene, at: Vector3, limit: Vector3, turn: float) -> void:
	var model := scene.instantiate() as Node3D
	add_child(model)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box := (
			(model.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
		)
		bounds = box if first else bounds.merge(box)
		first = false
	var scale_value := minf(
		limit.x / bounds.size.x, minf(limit.y / bounds.size.y, limit.z / bounds.size.z)
	)
	bounds = Transform3D(Basis(Vector3.UP, turn), Vector3.ZERO) * bounds
	model.scale = Vector3.ONE * scale_value
	model.position = (
		at - Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * scale_value
	)
	model.rotation.y = turn
	FINISH.apply_finishes(model)
	# Conservative fitted cover collision; reserve the complete set's approach separately.
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size * scale_value
	collision.shape = shape
	collision.position = at + Vector3.UP * shape.size.y * .5
	body.add_child(collision)
	add_child(body)
