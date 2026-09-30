extends RefCounted
## A stable connected route graph; catalogue population changes independently by seed.

const ROOMS := preload("res://features/casino_wing/room_kit.gd")
const KIT := preload("res://features/procedural_rooms/example_kit.gd")
const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const POPULATION := preload("res://features/procedural_rooms/room_population.gd")
const CATALOGUE := preload("res://features/casino_wing/catalogue.gd")
const DOOR := preload("res://features/procedural_rooms/sliding_door.tscn")
const CARPET := preload("res://features/casino_hub/materials/carpet.tres")
const WALL := preload("res://features/casino_hub/materials/wallpaper.tres")
const CEILING := preload("res://features/casino_hub/materials/ceiling.tres")
const TILE := preload("res://features/casino_hub/materials/tile.tres")
const PLASTER := preload("res://features/casino_hub/materials/plaster.tres")
const OPAL := preload("res://features/casino_hub/materials/opal.tres")
const STEEL := preload("res://features/casino_hub/materials/chrome.tres")
const BRASS := preload("res://features/casino_hub/materials/brass.tres")
const SHOWCASE := preload("res://features/procedural_rooms/showcase.gd")


static func build(parent: Node3D, seed_value: int = 1964, live: bool = true) -> Node3D:
	var level := Node3D.new()
	level.name = "Wing"
	parent.add_child(level)
	var entrance := _room(level, "Promenade", 4, 48)
	if live:
		(entrance.get_node("In") as ProceduralSocketAttachment).open("casino-north-wing")
	var gaming := _room(level, "GamingHall", 24, 20)
	_join(entrance, "Out", gaming, "In", "gaming-entry")
	var lounge := _room(level, "Lounge", 14, 10)
	_join(gaming, "West", lounge, "In", "lounge")
	var cards := _room(level, "CardRoom", 14, 12)
	_join(gaming, "East", cards, "In", "cards")
	var junction := _room(level, "Crossroads", 6, 20)
	_join(gaming, "Out", junction, "In", "crossroads")
	var hall := _room(level, "OfficeHall", 4, 8)
	_join(junction, "West", hall, "In", "office-hall")
	var corner := _room(level, "OfficeCorner", 4, 4)
	_join(hall, "Out", corner, "In", "office-corner")
	var office := _room(level, "Office", 12, 10)
	_join(corner, "East", office, "In", "office")
	var bar := _room(level, "BarLounge", 18, 12)
	_join(junction, "East", bar, "In", "bar")
	var stairs := KIT.connector("VaultStairs", "stairs")
	level.add_child(stairs)
	_join(junction, "Out", stairs, "Out", "vault-descent")
	var lobby := _room(level, "VaultLobby", 10, 16)
	_join(stairs, "In", lobby, "In", "vault-lobby")
	var security := _room(level, "SecurityOffice", 12, 10)
	_join(lobby, "West", security, "In", "security")
	var counting := _room(level, "CountingRoom", 12, 12)
	_join(lobby, "East", counting, "In", "counting")
	var vault := _room(level, "Vault", 16, 16)
	_join(lobby, "Out", vault, "In", "vault-door")
	var door := DOOR.instantiate() as ProceduralSlidingDoor
	door.name = "VaultDoor"
	door.door_label = "vault door"
	door.panel_material = STEEL
	door.frame_material = BRASS
	door.panel_depth = .28
	level.add_child(door)
	door.global_transform = (lobby.get_node("Out") as Node3D).global_transform
	_decorate_door(door)
	for module: Node3D in [lobby, security, counting, vault]:
		for face: Dictionary in module.get_meta("shell_faces"):
			if face["material"] == "floor":
				face["material"] = "vault_floor"
			elif face["material"] == "wall":
				face["material"] = "vault_wall"
	SHELL.rebuild(
		level,
		{
			"floor": CARPET,
			"wall": WALL,
			"grey": TILE,
			"roof": CEILING,
			"vault_floor": TILE,
			"vault_wall": PLASTER
		}
	)
	var definitions := CATALOGUE.definitions()
	_furnish(
		gaming,
		"gaming",
		["slot_bank", "cards", "lounge"],
		[Vector3(-7, 0, 4), Vector3(7, 0, 4), Vector3(-7, 0, 16), Vector3(7, 0, 16)],
		definitions,
		seed_value
	)
	_furnish(
		lounge,
		"lounge",
		["lounge"],
		[Vector3(-4.5, 0, 5), Vector3(4.5, 0, 5)],
		definitions,
		seed_value + 1
	)
	_furnish(
		cards,
		"cards",
		["cards"],
		[Vector3(-4.5, 0, 6), Vector3(4.5, 0, 6)],
		definitions,
		seed_value + 2
	)
	_furnish(
		bar, "bar", ["bar"], [Vector3(-6, 0, 6), Vector3(6, 0, 6)], definitions, seed_value + 3
	)
	_furnish(office, "office", ["office"], [Vector3(-3.7, 0, 5)], definitions, seed_value + 4)
	_furnish(security, "security", ["security"], [Vector3(-3.7, 0, 5)], definitions, seed_value + 5)
	_furnish(
		counting,
		"counting",
		["counting", "gold_rack"],
		[Vector3(-3.7, 0, 5), Vector3(3.7, 0, 9)],
		definitions,
		seed_value + 6
	)
	_furnish(
		vault,
		"vault",
		["vault_safes", "gold_rack"],
		[Vector3(-5, 0, 4), Vector3(5, 0, 4), Vector3(-5, 0, 11), Vector3(5, 0, 11)],
		definitions,
		seed_value + 7
	)
	return level


static func _room(parent: Node3D, id: String, width: float, length: float) -> Node3D:
	var room := ROOMS.room(id, width, length)
	parent.add_child(room)
	var marker := GpsDestination.new()
	marker.name = "GPS"
	marker.label = "Crown " + id.capitalize()
	marker.hint = "Casino north wing / vault stairs"
	marker.position = Vector3(0, 0, length * .5)
	room.add_child(marker)
	var sign := SHOWCASE.placard(room, id.capitalize(), Vector3(0, 2.6, 1))
	sign.font_size = 28
	sign.modulate = Color("d8bd82")
	for z: int in range(3, int(length), 6):
		KIT.box(
			room, "CeilingLight%d" % z, Vector3(1.8, .06, .45), Vector3(0, 3.38, z), OPAL, false
		)
	return room


static func _join(from: Node3D, out: String, to: Node3D, entrance: String, id: String) -> void:
	var errors := ProceduralSocketAttachment.attach(from.get_node(out), to.get_node(entrance), id)
	assert(errors.is_empty(), ", ".join(errors))


static func _furnish(
	room: Node3D,
	role: String,
	kinds: Array[String],
	slots: Array[Vector3],
	definitions: Array[ProceduralSetDefinition],
	seed_value: int
) -> void:
	var dimensions: Vector3 = room.get_meta("dimensions")
	var rule := ProceduralPopulationRule.new()
	rule.set_definitions = definitions
	rule.room_tag = role
	rule.allowed_sets = kinds
	rule.weights = PackedFloat32Array()
	rule.allowed_yaws = PackedFloat32Array([0, PI])
	if role == "vault":
		rule.allowed_yaws = PackedFloat32Array([0])
		rule.weights = PackedFloat32Array([4, 1])
	rule.density = 1
	rule.placement_bounds = AABB(Vector3(-dimensions.x * .5, 0, 0), dimensions)
	rule.slots = slots
	rule.forbidden_volumes = [AABB(Vector3(-1.5, 0, 0), Vector3(3, 4, dimensions.z))]
	for side: String in ["West", "East"]:
		if not (room.get_node(side) as ProceduralSocketAttachment).join_id.is_empty():
			rule.forbidden_volumes.append(
				AABB(
					Vector3(-dimensions.x * .5, 0, dimensions.z * .5 - 1.5),
					Vector3(dimensions.x, 4, 3)
				)
			)
	POPULATION.populate(room, rule, seed_value)
	room.set_meta("population_rule", rule)


static func _decorate_door(door: ProceduralSlidingDoor) -> void:
	for window: Node in door.find_children("Window", "", true, false):
		window.free()
	var plate := door.find_child("Panel", true, false) as Node3D
	KIT.box(plate, "LockWheelHorizontal", Vector3(.8, .08, .08), Vector3(0, 0, -.2), BRASS, false)
	KIT.box(plate, "LockWheelVertical", Vector3(.08, .8, .08), Vector3(0, 0, -.2), BRASS, false)
	SHOWCASE.placard(door, "VAULT / E TO OPEN", Vector3(0, 3.35, -.2))
