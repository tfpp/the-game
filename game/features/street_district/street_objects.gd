extends Node3D
## Shared interactive props stay outside streamed geometry on every peer.

const DUMPSTER := preload("res://features/slum_alley/dumpster.tscn")
const LOOT := preload("res://features/loot/loot_container.tscn")
const TABLE := preload("res://features/slum_alley/alley_loot.tres")
const CAR := preload("res://features/procedural_rooms/props/car.tscn")
const BIN_POSITIONS: Array[Vector3] = [
	Vector3(-18, 0, -5.15),
	Vector3(18, 0, -5.15),
	Vector3(-18, 0, 22.85),
	Vector3(18, 0, 22.85),
	Vector3(-33.15, 0, 14),
	Vector3(33.15, 0, 42),
]


func _ready() -> void:
	for i: int in BIN_POSITIONS.size():
		var bin := DUMPSTER.instantiate() as Node3D
		bin.name = "Dumpster%d" % i
		bin.position = BIN_POSITIONS[i]
		bin.rotation.y = 0 if i < 4 else (PI / 2 if i == 4 else -PI / 2)
		var loot := LOOT.instantiate() as LootContainer
		loot.name = "Loot"
		loot.position = Vector3(0, .9, 1.1)
		loot.noun = "dumpster"
		loot.loot_table = TABLE
		bin.add_child(loot)
		add_child(bin)
	for row: int in range(3):
		for side: int in [-1, 1]:
			var car := CAR.instantiate() as Node3D
			car.name = "Car%d%s" % [row, "West" if side < 0 else "East"]
			car.position = Vector3(side * 14, 0, row * 28 + side * 2.8)
			car.rotation.y = side * PI / 2
			add_child(car)
