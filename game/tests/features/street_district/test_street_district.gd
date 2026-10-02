extends GutTest

const LAYOUT := preload("res://features/street_district/layout.gd")
const KIT := preload("res://features/street_district/street_kit.gd")
const GARAGE := preload("res://features/procedural_rooms/example_kit.gd")
const PLAYER := preload("res://core/player/player.tscn")
var _world: Node3D
var _saved_device: Controls.Device
var _saved_playing: bool


func before_each() -> void:
	_saved_device = Controls.device
	_saved_playing = Controls.playing
	_world = Node3D.new()
	add_child_autofree(_world)
	LAYOUT.build(_world)
	await wait_physics_frames(3)


func after_each() -> void:
	Controls.device = _saved_device
	Controls.playing = _saved_playing
	Controls.xr_move = Vector2.ZERO


func test_connected_graph_uses_exact_garage_attachments_and_owned_caps() -> void:
	var district := _world.get_node("District") as Node3D
	var joins: Array = district.get_meta("joins")
	assert_eq(joins.size(), 36)
	var graph: Dictionary[Node, Array] = {}
	for join: Dictionary in joins:
		var a := join["from"] as ProceduralSocketAttachment
		var b := join["to"] as ProceduralSocketAttachment
		assert_true(a.errors_with(b).is_empty())
		assert_eq(a.join_id, b.join_id)
		assert_null(a.cap)
		assert_null(b.cap)
		for pair: Array in [[a.get_parent(), b.get_parent()], [b.get_parent(), a.get_parent()]]:
			if not graph.has(pair[0]):
				graph[pair[0]] = []
			graph[pair[0]].append(pair[1])
	var reached: Array[Node] = []
	var pending: Array[Node] = [district.get_node("J00")]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if reached.has(node):
			continue
		reached.append(node)
		for next: Node in graph[node]:
			pending.append(next)
	assert_eq(reached.size(), 29)
	var caps := 0
	for socket: ProceduralSocketAttachment in district.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			assert_not_null(socket.cap)
			caps += 1
	assert_eq(caps, 38)


func test_every_join_supports_and_clears_a_standing_player() -> void:
	var space := _world.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = .4064
	shape.height = 1.8288
	for join: Dictionary in _world.get_node("District").get_meta("joins"):
		var socket := join["from"] as ProceduralSocketAttachment
		var edge := socket.profile.width / 2 - .6
		for side: float in [-edge, 0.0, edge]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform.origin = socket.to_global(Vector3(side, .9544, -.6))
			query.motion = socket.global_basis.z * 1.2
			assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, socket.join_id)
			for offset: float in [-.3, 0.0, .3]:
				var point := socket.to_global(Vector3(side, 0, offset))
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN)
				)
				if is_zero_approx(offset):
					# Ray hits on an exact triangle edge are not reliable; probe the seam itself.
					var probe := PhysicsShapeQueryParameters3D.new()
					var sphere := SphereShape3D.new()
					sphere.radius = .001
					probe.shape = sphere
					probe.transform.origin = point
					assert_false(space.intersect_shape(probe).is_empty(), socket.join_id)
				else:
					assert_false(hit.is_empty(), "%s / %s / %s" % [socket.join_id, side, point])
				if not hit.is_empty():
					assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)


func test_unused_exits_block_travel_and_alley_profiles_match_garage() -> void:
	var space := _world.get_world_3d().direct_space_state
	for socket: ProceduralSocketAttachment in _world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if not socket.join_id.is_empty():
			continue
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(
				socket.to_global(Vector3(0, 1, -2)), socket.to_global(Vector3(0, 1, 1))
			)
		)
		assert_false(hit.is_empty(), str(socket.get_parent().name))
	var alley := KIT.alley("CompatibilityAlley")
	var garage := GARAGE.connector("CompatibilityGarage", "hall")
	_world.add_child(alley)
	_world.add_child(garage)
	assert_eq(
		ProceduralSocketAttachment.attach(
			alley.get_node("Out"), garage.get_node("In"), "garage-compatible"
		),
		[]
	)
	var wide := KIT.street("WideStreet")
	_world.add_child(wide)
	assert_eq(
		ProceduralSocketAttachment.attach(
			wide.get_node("Out"), garage.get_node("Out"), "wrong-profile"
		),
		["Opening profiles differ"]
	)


func test_actual_controller_traverses_all_alleys_both_directions() -> void:
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for id: String in ["Alley00", "Alley01", "Alley10", "Alley11"]:
		var alley := _world.get_node("District/" + id) as Node3D
		for reverse: bool in [false, true]:
			player.position = alley.to_global(Vector3(0, .9644, 16.7 if reverse else -.7))
			player.velocity = Vector3.ZERO
			player.yaw = 0.0 if reverse else PI
			Controls.xr_move = Vector2(0, -.5)
			for frame: int in range(500):
				player._physics_process(1.0 / 64)
				await wait_physics_frames(1)
				var local := alley.to_local(player.position)
				if local.z < -.6 if reverse else local.z > 16.6:
					break
			var final := alley.to_local(player.position)
			assert_true(final.z < -.5 if reverse else final.z > 16.5, id)
			assert_almost_eq(final.y - player.movement.hull_height_m() * .5, 0.0, .06)
	player.free()


func test_rooms_stay_inside_their_building_envelopes() -> void:
	var district := _world.get_node("District")
	for id: String in ["ShopFront", "ShopBack", "WorkshopFront", "WorkshopBack"]:
		var room := district.get_node(id) as Node3D
		var building := room.get_meta("building") as Node3D
		var dimensions: Vector3 = room.get_meta("dimensions")
		for x: float in [-dimensions.x / 2, dimensions.x / 2]:
			for y: float in [0.0, dimensions.y]:
				for z: float in [0.0, dimensions.z]:
					var point := building.to_local(room.to_global(Vector3(x, y, z)))
					assert_lte(absf(point.x), 3.0001, id)
					assert_lte(absf(point.z), 7.1001, id)
					assert_gte(point.y, -.0001, id)
					assert_lte(point.y, 6.0, id)


func test_actual_player_enters_back_rooms_and_returns_to_the_street() -> void:
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for id: String in ["ShopFront", "WorkshopFront"]:
		var room := _world.get_node("District/" + id) as Node3D
		for reverse: bool in [false, true]:
			player.position = room.to_global(Vector3(0, .9644, 12.0 if reverse else -.7))
			player.velocity = Vector3.ZERO
			player.yaw = 0.0 if reverse else PI
			Controls.xr_move = Vector2(0, -.5)
			for frame: int in range(400):
				player._physics_process(1.0 / 64)
				await wait_physics_frames(1)
				var local := room.to_local(player.position)
				if local.z < -.6 if reverse else local.z > 11.6:
					break
			var final := room.to_local(player.position)
			assert_true(final.z < -.5 if reverse else final.z > 11.5, id)
			assert_almost_eq(final.y - player.movement.hull_height_m() * .5, 0.0, .06)
	player.free()


func test_lamps_and_seating_face_the_street() -> void:
	var district := _world.get_node("District")
	var checked := 0
	for street: Node in district.get_children():
		if not street.name.begins_with("H"):
			continue
		for prop: Node in street.get_children():
			if not prop is Node3D:
				continue
			var front := Vector3.ZERO
			if prop.name.begins_with("StreetLamp"):
				front = prop.basis.x
			elif prop.name.begins_with("StreetBench") or prop.name.begins_with("BusShelter"):
				front = prop.basis.z
			else:
				continue
			var toward_road := Vector3(-signf(prop.position.x), 0, 0)
			assert_gt(front.normalized().dot(toward_road), .99, str(prop.name))
			checked += 1
	assert_gt(checked, 0)
