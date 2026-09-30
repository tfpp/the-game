class_name CarBoot
extends LootContainer
## Server-derived gaze opens the boot without rolling loot. Normal Use searches it.

@export var net_boot_open := false
@export var hinge_path := NodePath("../BootLid")
@export var hinge_axis := Vector3(0, 0, 1)
@export var open_degrees := -68.0
@export var boot_size := Vector3(1.15, .8, 1.9)
@export var approach_axis := Vector3.LEFT
@export var collision_path := NodePath("..")
var _amount := 0.0
var _check_in := 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"car_boots")
	_entity.session_reset.connect(_reset_boot)
	_amount = 1.0 if net_boot_open else 0.0
	_pose()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server():
		return
	_check_in -= delta
	if _check_in > 0:
		return
	_check_in = .1
	net_boot_open = net_active_searchers > 0
	if net_boot_open:
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if can_use(node as Player):
			net_boot_open = true
			break


func _process(delta: float) -> void:
	_amount = move_toward(_amount, 1.0 if net_boot_open else 0.0, delta / .4)
	_pose()


func _pose() -> void:
	var hinge := get_node_or_null(hinge_path) as Node3D
	if hinge != null:
		hinge.rotation = hinge_axis * deg_to_rad(open_degrees) * smoothstep(0.0, 1.0, _amount)


func can_use(player: Player) -> bool:
	if not super.can_use(player):
		return false
	var eye := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
	)
	var yaw := player.yaw if player.is_local() else player.net_yaw
	var pitch := player.pitch if player.is_local() else player.net_pitch
	var direction := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD
	var local_eye := to_local(eye)
	if local_eye.dot(approach_axis) < .35:
		return false
	var local_direction := global_basis.inverse() * direction
	var box := AABB(-boot_size * .5, boot_size)
	var intersection: Variant = box.intersects_ray(local_eye, local_direction)
	if intersection == null:
		return false
	var hit := to_global(intersection as Vector3)
	if (hit - eye).dot(direction) < 0 or eye.distance_to(hit) > search_range:
		return false
	# The car's stable cover hull encloses the cavity; ignore it, but not walls or other cars.
	var query := PhysicsRayQueryParameters3D.create(eye, hit)
	var excluded: Array[RID] = [player.get_rid()]
	var body := get_node_or_null(collision_path) as CollisionObject3D
	if body != null:
		excluded.append(body.get_rid())
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _reset_boot(_mode: Network.Mode) -> void:
	if multiplayer.is_server():
		net_boot_open = false
	_check_in = 0.0
