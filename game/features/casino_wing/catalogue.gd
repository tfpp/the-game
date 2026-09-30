extends RefCounted

const SCENES: Dictionary[String, PackedScene] = {
	"slot_bank": preload("res://features/casino_wing/sets/slot_bank.tscn"),
	"cards": preload("res://features/casino_wing/sets/cards.tscn"),
	"bar": preload("res://features/casino_wing/sets/bar.tscn"),
	"lounge": preload("res://features/casino_wing/sets/lounge.tscn"),
	"office": preload("res://features/casino_wing/sets/office.tscn"),
	"security": preload("res://features/casino_wing/sets/security.tscn"),
	"counting": preload("res://features/casino_wing/sets/counting.tscn"),
	"vault_safes": preload("res://features/casino_wing/sets/vault_safes.tscn"),
	"gold_rack": preload("res://features/casino_wing/sets/gold_rack.tscn")
}


static func definitions() -> Array[ProceduralSetDefinition]:
	var result: Array[ProceduralSetDefinition] = []
	var sizes := {
		"slot_bank": Vector3(4, 2.5, 2),
		"cards": Vector3(4.8, 2, 4.8),
		"bar": Vector3(6, 3, 4),
		"lounge": Vector3(4.8, 2, 3),
		"office": Vector3(4, 2, 3.6),
		"security": Vector3(4, 2, 3.6),
		"counting": Vector3(4, 2, 3.6),
		"vault_safes": Vector3(4, 2.5, 1.5),
		"gold_rack": Vector3(4, 2, 1.8)
	}
	var roles := {
		"slot_bank": ["gaming", "slots"],
		"cards": ["gaming", "cards"],
		"bar": ["bar"],
		"lounge": ["gaming", "lounge", "lobby"],
		"office": ["office"],
		"security": ["security"],
		"counting": ["counting"],
		"vault_safes": ["vault"],
		"gold_rack": ["vault", "counting"]
	}
	for id: String in SCENES:
		var definition := ProceduralSetDefinition.new()
		definition.id = id
		definition.scene = SCENES[id]
		definition.footprint = sizes[id]
		definition.allowed_rooms.assign(roles[id])
		result.append(definition)
	return result
