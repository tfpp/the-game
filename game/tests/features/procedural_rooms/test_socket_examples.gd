extends GutTest

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Layout := preload("res://features/procedural_rooms/example_layout.gd")
const PLAYER := preload("res://core/player/player.tscn")
var _world: Node3D
var _old_device: int
var _old_playing: bool


func before_each() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	_world = Layout.build(host)
	_old_device = Controls.device
	_old_playing = Controls.playing
	await wait_physics_frames(2)


func after_each() -> void:
	Controls.device = _old_device
	Controls.playing = _old_playing
	Controls.xr_move = Vector2.ZERO


func test_all_eight_joins_have_matching_boundaries_and_removed_caps() -> void:
	var joins: Dictionary[String, Array] = {}
	for socket: ProceduralSocketAttachment in _world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			assert_not_null(socket.cap)
			continue
		assert_null(socket.cap)
		if not joins.has(socket.join_id):
			joins[socket.join_id] = []
		joins[socket.join_id].append(socket)
	assert_eq(joins.size(), 8)
	for sockets: Array in joins.values():
		assert_eq(sockets.size(), 2)
		assert_eq(sockets[0].errors_with(sockets[1]), [])


func test_attachment_snapping_matches_all_four_yaw_rotations() -> void:
	for quarter: int in 4:
		var a := Kit.room("A")
		var b := Kit.room("B")
		_world.add_child(a)
		_world.add_child(b)
		a.position = Vector3(90, 4, 90)
		a.rotation.y = quarter * PI * 0.5
		var from := a.get_node("Out") as ProceduralSocketAttachment
		var to := b.get_node("In") as ProceduralSocketAttachment
		b.global_transform = from.placement_for(to)
		assert_eq(from.errors_with(to), [])
		a.free()
		b.free()


func test_mismatched_profiles_and_misaligned_boundaries_are_rejected() -> void:
	var a := _world.get_node("Routes/Ramp/Arrival/Out") as ProceduralSocketAttachment
	var b := _world.get_node("Routes/Ramp/Ramp/In") as ProceduralSocketAttachment
	b.profile = b.profile.duplicate() as ProceduralSocketProfile
	b.profile.width = 4.0
	assert_true("Opening profiles differ" in a.errors_with(b))
	b.profile.width = 3.0
	b.position.y += 0.02
	assert_true("Floor origins do not align" in a.errors_with(b))
	assert_true("Opening boundary does not align" in a.errors_with(b))


func test_bad_and_used_attachments_preserve_placement_and_caps() -> void:
	var a := Kit.room("FreeA")
	var b := Kit.room("FreeB")
	_world.add_child(a)
	_world.add_child(b)
	b.position = Vector3(90, 0, 90)
	var original := b.global_transform
	var from := a.get_node("Out") as ProceduralSocketAttachment
	var to := b.get_node("In") as ProceduralSocketAttachment
	to.profile = to.profile.duplicate() as ProceduralSocketProfile
	to.profile.width = 4
	assert_eq(ProceduralSocketAttachment.attach(from, to, "bad"), ["Opening profiles differ"])
	assert_eq(b.global_transform, original)
	assert_not_null(from.cap)
	assert_not_null(to.cap)
	to.profile.width = 3
	assert_eq(ProceduralSocketAttachment.attach(from, to, "valid"), [])
	assert_eq(
		ProceduralSocketAttachment.attach(from, to, "duplicate"), ["Socket is already attached"]
	)
	assert_eq(from.join_id, "valid")
	a.free()
	b.free()


func test_every_join_has_floor_support_and_full_capsule_clearance() -> void:
	var space := _world.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4064
	shape.height = 1.8288
	for socket: ProceduralSocketAttachment in _world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty():
			continue
		for side: float in [-0.7, 0.0, 0.7]:
			var start := socket.to_global(Vector3(side, 0.9544, -0.6))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis.IDENTITY, start)
			query.motion = socket.global_basis.z * 1.2
			var sweep := space.cast_motion(query)
			assert_almost_eq(sweep[0], 1.0, 0.001, socket.join_id + " capsule crossing")
			for offset: float in [-0.3, 0.0, 0.3]:
				var point := socket.to_global(Vector3(side, 0, offset))
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN)
				)
				assert_false(hit.is_empty(), socket.join_id + " floor support")
				if not hit.is_empty():
					assert_almost_eq(hit["position"].y, point.y, 0.001)


func test_actual_player_climbs_and_descends_ramp_and_stairs() -> void:
	Controls.device = Controls.Device.XR
	Controls.playing = true
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	for kind: String in ["Ramp", "Stairs"]:
		var module := _world.get_node("Routes/" + kind + "/" + kind) as Node3D
		var length: float = module.get_meta("length")
		for reverse: bool in [false, true]:
			player.position = module.to_global(
				Vector3(0, 4.9644 if reverse else 0.9644, length + 0.7 if reverse else -0.7)
			)
			player.velocity = Vector3.ZERO
			player.yaw = 0.0 if reverse else PI
			Controls.xr_move = Vector2.ZERO
			for frame: int in 12:
				player._physics_process(1.0 / 64.0)
				await wait_physics_frames(1)
			Controls.xr_move = Vector2(0, -0.5)
			for frame: int in ceili((length + 2) * 64 / 3) + 64:
				player._physics_process(1.0 / 64.0)
				await wait_physics_frames(1)
				var local := module.to_local(player.position)
				if local.z < -0.6 if reverse else local.z > length + 0.6:
					break
			var final := module.to_local(player.position)
			assert_true(
				final.z < -0.5 if reverse else final.z > length + 0.5,
				kind + " actual controller traversal"
			)
			assert_almost_eq(
				final.y - player.movement.hull_height_m() * 0.5, 0.0 if reverse else 4.0, 0.06
			)
	player.free()
