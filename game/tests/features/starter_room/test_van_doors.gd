extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")
const DOORS: Array[String] = ["DriverDoor", "PassengerDoor", "RearLeftDoor", "RearRightDoor"]
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var feature := FEATURE.instantiate() as Node3D
	feature.name = "StarterRoom"
	root.add_child(feature)
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	(feature.get_node("TravelPanel") as VanTravelPanel).set_process(false)
	return feature.get_node("Room/Van/Model") as Node3D


func _door(model: Node3D, title: String) -> OperationsVanDoor:
	return model.get_node(title) as OperationsVanDoor


func test_authenticated_doors_replicate_to_late_join_and_reject_distant_or_spoofed_use() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("VanServer", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("VanClient", client_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var player := PLAYER.instantiate() as Player
	player.name = str(client_peer.get_unique_id())
	player.set_multiplayer_authority(client_peer.get_unique_id())
	player.get_node("Sync").free()
	server.get_parent().get_parent().get_parent().add_child(player)
	player.set_physics_process(false)
	for title: String in DOORS:
		var door := _door(server, title)
		var remote := _door(client, title)
		player.net_position = door.global_position + Vector3(-5, 0, 0)
		assert_eq(
			door.entity._evaluate(player.get_multiplayer_authority(), &"use", {}),
			NetworkedEntity.Result.DENIED
		)
		player.net_position = door.global_position + Vector3(0, 0, -.3)
		assert_eq(
			door.entity._evaluate(player.get_multiplayer_authority(), &"use", {"peer": 1}),
			NetworkedEntity.Result.DENIED
		)
		assert_eq(remote.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
		remote.use()
		assert_true(
			await REAL_TIME.wait_until(get_tree(), func() -> bool: return remote.net_open, 5)
		)
		assert_true(door.net_open)
		remote.use()
		await REAL_TIME.wait(get_tree(), .1)
		assert_true(door.net_open, "Repeated use during the swing is ignored")
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("VanLate", late_peer)
	for title: String in DOORS:
		var observer := _door(late, title)
		assert_true(
			await REAL_TIME.wait_until(
				get_tree(),
				func() -> bool:
					return (
						observer.net_open
						and absf(observer.hinge.rotation.y - observer.open_angle) < .001
					),
				5
			)
		)
		var door := _door(server, title)
		player.net_position = door.to_global(door.entity.interaction_offset)
		_door(client, title).use()
		assert_true(
			await REAL_TIME.wait_until(get_tree(), func() -> bool: return not observer.net_open, 5)
		)
	assert_false((client.get_parent() as OperationsVan).panel.is_open())


func test_exported_armour_and_leaves_have_valid_geometry_and_keep_small_approved_atlas() -> void:
	var scene := preload("res://features/starter_room/van_model.tscn").instantiate() as Node3D
	add_child_autofree(scene)
	var triangles := 0
	for node: Node in scene.find_children("*", "MeshInstance3D"):
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		for i: int in vertices.size():
			assert_true(vertices[i].is_finite())
			if node.get_parent().get_parent().name in ["DriverDoor", "PassengerDoor"]:
				var point: Vector3 = (node as Node3D).global_transform * vertices[i]
				assert_lte(point.y, 2.13, "Cab hardware fits below the roof")
				if point.y > 1.5 and absf(point.x) <= 1.006:
					assert_lte(
						point.y + point.z * (0.9 / .55),
						4.05,
						"Upper door skin follows the windshield rake"
					)
			assert_almost_eq(normals[i].length(), 1.0, .001)
			assert_true(uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1)
		for i: int in range(0, indices.size(), 3):
			var a := indices[i]
			var cross := (vertices[indices[i + 1]] - vertices[a]).cross(
				vertices[indices[i + 2]] - vertices[a]
			)
			assert_gt(cross.length(), .000001)
			assert_lt(cross.normalized().dot(normals[a]), -.99)
	assert_lt(triangles, 1500)
	assert_almost_eq(
		(scene.get_node("Body") as MeshInstance3D).mesh.get_aabb().position.y, 0.0, .001
	)
	assert_eq(preload("res://assets/starter_room/van.png").get_size(), Vector2(128, 128))
	assert_eq(preload("res://assets/starter_room/van_cab.png").get_size(), Vector2(128, 128))


func test_open_leaves_move_collision_clear_of_cab_and_cargo_openings() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	(feature.get_node("TravelPanel") as VanTravelPanel).set_process(false)
	var model := feature.get_node("Room/Van/Model") as Node3D
	await wait_physics_frames(3)
	var space := model.get_world_3d().direct_space_state
	for side: float in [-1, 1]:
		var above_rake := PhysicsRayQueryParameters3D.create(
			model.to_global(Vector3(side * 1.8, 1.9, 1.5)),
			model.to_global(Vector3(side * .85, 1.9, 1.5))
		)
		assert_true(
			space.intersect_ray(above_rake).is_empty(),
			"No invisible door collision above the sloped front edge"
		)
	var rays: Array[Array] = [
		["DriverDoor", Vector3(-1.8, 1.2, 1), Vector3(-.85, 1.2, 1)],
		["RearLeftDoor", Vector3(-.45, 1.3, -3.2), Vector3(-.45, 1.3, -1.8)],
		["RearRightDoor", Vector3(.45, 1.3, -3.2), Vector3(.45, 1.3, -1.8)]
	]
	for ray: Array in rays:
		var query := PhysicsRayQueryParameters3D.create(
			model.to_global(ray[1]), model.to_global(ray[2])
		)
		assert_false(space.intersect_ray(query).is_empty(), "Closed leaf blocks the opening")
		var door := _door(model, ray[0])
		door.net_open = true
		await wait_physics_frames(40)
		assert_true(space.intersect_ray(query).is_empty(), "Open leaf clears the opening")
		assert_almost_eq(door.hinge.rotation.y, door.open_angle, .001)
