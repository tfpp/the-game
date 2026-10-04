class_name SlumInstance
extends ZoneScope
## One server-created excursion. Only its members receive its spawned subtree.

enum Destination { GARAGE, ALLEYS }

const GARAGE_LAYOUT := preload("res://features/procedural_rooms/world_layout.gd")
const GARAGE_COLLISION := preload("res://features/zone_instances/garage_gridmap/collision.tscn")
const ALLEY_SCENE := "res://features/slum_alley/alley.tscn"
const RENDER_ZONE := preload("res://features/room_visibility/render_zone.gd")
const ATMOSPHERE := preload("res://features/procedural_rooms/garage_atmosphere.gd")
const ELEVATOR := preload("res://features/elevator/elevator.tscn")
const ENCOUNTER_POINTS := preload("res://features/zone_instances/encounter_points.tscn")
const ENEMY := preload("res://features/garage_enemies/garage_enemy.tscn")
const LOOT := preload("res://features/loot/loot_container.tscn")
const CRATE := preload("res://features/procedural_rooms/props/crate.tscn")
const ARRIVAL_LIGHT := preload("res://features/parking_garage/fluorescent_fixture.tscn")
const ARRIVAL_LIGHT_MOUNT := preload("res://features/slum_alley/arrival_light_mount.tscn")

@export var destination: Destination = Destination.GARAGE
@export var layout_seed := 73021
var arrival: Marker3D
var return_cab: ElevatorCab
var ready_peers: Array[int] = []
var enemy_plan: Array[Dictionary] = []


func entry_position() -> Vector3:
	return return_cab.car.to_global(Vector3(0, .95, -.4))


func _ready() -> void:
	super._ready()
	if destination == Destination.GARAGE:
		_build_garage()
	else:
		_build_alleys()
	_build_return_cab()
	_report_loaded.call_deferred()


func _report_loaded() -> void:
	for service: Node in get_tree().get_nodes_in_group(&"zone_instances"):
		if service.multiplayer == multiplayer:
			service.call("report_loaded", instance_id)
			return


func _build_return_cab() -> void:
	var elevator := ELEVATOR.instantiate() as Node3D
	elevator.name = "ReturnElevator"
	return_cab = elevator.get_node("Cab") as ElevatorCab
	return_cab.excursion_role = ElevatorCab.ExcursionRole.RETURN
	return_cab.sign_text = "GOLDEN CROWN"
	return_cab.home_floor = "B1" if destination == Destination.GARAGE else "A"
	elevator.position = (
		Vector3(0, 16, 0) if destination == Destination.GARAGE else Vector3(0, 0, 23)
	)
	elevator.rotation.y = 0.0 if destination == Destination.GARAGE else PI
	add_child(elevator)
	if destination == Destination.GARAGE:
		# This deck's ceiling is 3.5 m; the Crown's tall header would sit above it.
		var sign := return_cab.get_node("Car/Sign") as SignBoard
		sign.position.y = 3.2
		sign.letter_height = .18
		sign.padding = .025
		(return_cab.get_node("Car/Indicator") as Node3D).position.y = 2.98
		(return_cab.get_node("Car/HallLamp") as Node3D).position.y = 3.0
	else:
		var light := ARRIVAL_LIGHT.instantiate() as FluorescentLight
		light.name = "ArrivalLight"
		light.position = Vector3(0, 4.15, 2.2)
		light.mode = FluorescentLight.Mode.STEADY
		light.base_energy = 4.5
		light.light_color = Color("ffd39a")
		light.fixture_seed = 916
		elevator.add_child(light)
		elevator.add_child(ARRIVAL_LIGHT_MOUNT.instantiate())


func _build_garage() -> void:
	var map := RenderZone.new()
	map.name = "Map"
	map.render_layer = 20
	map.render_bounds = ATMOSPHERE.BOUNDS
	add_child(map)
	var world := GARAGE_LAYOUT.build(map, layout_seed, [], false, false)
	# The top landing serves the excursion cab rather than the internal service lift.
	world.get_node("Deck4/ElevatorSign").free()
	if multiplayer.is_server():
		var collision := GARAGE_COLLISION.instantiate() as Node3D
		collision.name = "StructureCollision"
		world.add_child(collision)
	var structure := StreamedRoom.new()
	structure.name = "Structure"
	structure.room_scene = "res://features/zone_instances/garage_gridmap/static.tscn"
	structure.bounds = ATMOSPHERE.BOUNDS
	world.add_child(structure)
	# Root spawning already restricts the scene to its members. Preload before
	# acknowledging readiness; RoomVisibility owns its subsequent content lifetime.
	if not multiplayer.is_server() or multiplayer.get_unique_id() in members:
		structure.load_room(10000)
		if multiplayer.is_server():
			var grid := structure.get_node("Content/Levels") as GridMap
			grid.collision_layer = 0
			grid.collision_mask = 0
	_populate_garage(world)
	var weather := ATMOSPHERE.new()
	weather.name = "Atmosphere"
	map.add_child(weather)
	arrival = Marker3D.new()
	arrival.name = "Arrival"
	arrival.position = Vector3(0, 17, 5)
	map.add_child(arrival)


func _populate_garage(world: Node3D) -> void:
	var points := ENCOUNTER_POINTS.instantiate() as Node3D
	world.add_child(points)
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	world.add_child(enemies)
	for index: int in enemy_plan.size():
		var entry: Dictionary = enemy_plan[index]
		var marker := (
			points.get_node("B%d/Enemy%d" % [int(entry["depth"]) + 1, int(entry["point"])])
			as Marker3D
		)
		var enemy := ENEMY.instantiate() as GarageEnemy
		enemy.name = "Enemy%d" % index
		enemy.tier = int(entry["tier"]) as GarageEnemyTiers.Tier
		if int(entry["depth"]) == 4:
			enemy.damage_scale = 1.5
			enemy.windup_scale = .75
		enemy.position = world.to_local(marker.global_position)
		enemies.add_child(enemy)
	var containers := Node3D.new()
	containers.name = "Loot"
	world.add_child(containers)
	for depth: int in 5:
		for point: int in 4:
			var marker := points.get_node("B%d/Loot%d" % [depth + 1, point]) as Marker3D
			var container := LOOT.instantiate() as LootContainer
			container.name = "B%dCrate%d" % [depth + 1, point]
			container.position = world.to_local(marker.global_position)
			container.loot_table = GarageRunPlan.loot_table(depth)
			container.noun = "B%d supply crate" % (depth + 1)
			container.rng.seed = layout_seed + depth * 7919 + point * 104729
			container.add_child(CRATE.instantiate())
			containers.add_child(container)


func _build_alleys() -> void:
	var map := (load(ALLEY_SCENE) as PackedScene).instantiate() as Node3D
	map.set_script(RENDER_ZONE)
	(map as RenderZone).render_layer = 19
	(map as RenderZone).render_bounds = AABB(Vector3(-26, -2, -26), Vector3(52, 40, 52))
	map.name = "Map"
	var district := map.get_node("District") as Node3D
	district.position = Vector3.ZERO
	# The copied scene is not a public destination and cannot retain a global gate.
	district.get_node("ReturnDoor").free()
	district.get_node("ReturnSign").free()
	_replace_exit_fence(district)
	add_child(map)
	arrival = district.get_node("Arrival") as Marker3D
	arrival.remove_from_group(&"slum_arrival_points")


func _replace_exit_fence(district: Node3D) -> void:
	# Leave an eight metre opening for the return facade rather than a collision
	# fence through the middle of the cab. The two remaining fence spans are tiles.
	var source := district.get_node("SouthFence") as CSGBox3D
	var material := source.material
	source.free()
	var library := MeshLibrary.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(20.5, 3.2, .12)
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	for tile: int in 2:
		var pose := Transform3D(Basis.IDENTITY, Vector3(-14.25 if tile == 0 else 14.25, 1.6, 24.5))
		library.create_item(tile)
		library.set_item_name(tile, "Exit fence left" if tile == 0 else "Exit fence right")
		library.set_item_mesh(tile, mesh)
		library.set_item_mesh_transform(tile, pose)
		library.set_item_shapes(tile, [shape, pose])
	var grid := GridMap.new()
	grid.name = "ExitFence"
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.mesh_library = library
	grid.set_cell_item(Vector3i.ZERO, 0)
	# Cancel the cell translation: each item's pose specifies its authored span.
	var right_pose := library.get_item_mesh_transform(1)
	right_pose.origin.x -= 1.0
	library.set_item_mesh_transform(1, right_pose)
	library.set_item_shapes(1, [shape, right_pose])
	grid.set_cell_item(Vector3i.RIGHT, 1)
	district.add_child(grid)
