class_name BlockPlayerModel
extends Node3D
## Angular low-polygon avatar with adult human proportions. Parent: Player/Body.
## The camera feature controls first/third-person visibility; replication owns yaw.

## Uniform rig scale for the "penguin" body type, so the third-person model (and,
## via `height_scale()`, the first-person view model in features/holdables/hand.gd)
## reads as short as the penguin NPC (features/penguin), not human-height in a suit.
const PENGUIN_HEIGHT_SCALE := 0.58

var player: Player
var skin_color := PlayerSkin.TONES[0]
var shirt_color := skin_color
var pants_color := skin_color
var shirt_id := ""
var pants_id := ""
var body_type: StringName = &"default"
var head_type: StringName = &"human"
var tail_type: StringName = &"none"
var locomotion: StringName = &"idle"
var _height_scale := 1.0
var _skin_material: StandardMaterial3D
var _shirt_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _pants_material: StandardMaterial3D
var _phase := 0.0
var _landing := 0.0
var _was_grounded := true
var _rig := Node3D.new()
var _torso := Node3D.new()
var _head := Node3D.new()
var _left_arm := Node3D.new()
var _right_arm := Node3D.new()
var _left_leg := Node3D.new()
var _right_leg := Node3D.new()
var _left_shoulder := Marker3D.new()
var _right_shoulder := Marker3D.new()
var _tail := Node3D.new()


func _ready() -> void:
	process_priority = 15
	_build()
	set_process(player != null)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var motion := player.velocity if player.is_local() else player.net_velocity
	var yaw := player.yaw if player.is_local() else (get_parent() as Node3D).global_rotation.y
	var local_motion := Basis(Vector3.UP, -yaw) * motion
	var grounded := player.is_on_floor() if player.is_local() else _remote_grounded()
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	if hand != null:
		set_skin_index(hand.skin_tone_index())
		set_clothing(hand.inventory().shirt, hand.inventory().pants)
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	if models != null:
		var peer_id := player.get_multiplayer_authority()
		set_body_type(models.type_for(peer_id))
		set_head_type(models.type_for_head(peer_id))
		set_tail_type(models.type_for_tail(peer_id))
	var holding := hand != null and ItemCatalog.find(hand.net_item_id) != null
	var support := holding and hand.support_grip() != null
	var pitch := player.pitch if player.is_local() else player.net_pitch
	animate(delta, local_motion, grounded, player.movement.max_speed_m(), pitch, holding, support)


func animate(
	delta: float,
	motion: Vector3,
	grounded: bool,
	max_speed: float,
	pitch: float = 0.0,
	right_held: bool = false,
	left_held: bool = false
) -> void:
	var speed := Vector2(motion.x, motion.z).length()
	if grounded and speed > BlockPlayerMotion.IDLE_SPEED:
		_phase = fmod(_phase + BlockPlayerMotion.phase_step(speed, max_speed, delta), TAU)
	if grounded and not _was_grounded:
		_landing = 1.0
	_was_grounded = grounded
	_landing = maxf(_landing - delta * 7.0, 0.0)
	var pose := BlockPlayerMotion.pose(_phase, motion, grounded, max_speed)
	locomotion = pose["state"]
	var blend := 1.0 - exp(-14.0 * delta)
	_left_leg.rotation.x = lerp_angle(_left_leg.rotation.x, pose["left_leg"], blend)
	_right_leg.rotation.x = lerp_angle(_right_leg.rotation.x, pose["right_leg"], blend)
	_left_arm.rotation.x = lerp_angle(_left_arm.rotation.x, pose["left_arm"], blend)
	_right_arm.rotation.x = lerp_angle(_right_arm.rotation.x, pose["right_arm"], blend)
	_left_arm.visible = not left_held
	_right_arm.visible = not right_held
	_torso.rotation.x = lerp_angle(_torso.rotation.x, pose["lean"], blend)
	_torso.rotation.z = lerp_angle(_torso.rotation.z, pose["roll"], blend)
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch - _torso.rotation.x, blend)
	_rig.scale = Vector3(_height_scale, _height_scale * (1.0 - _landing * 0.055), _height_scale)
	_rig.position.y = float(pose["bob"]) - _landing * 0.049


func shoulder_position(right: bool) -> Vector3:
	# HeldArms renders without physics interpolation; use the same interpolated
	# shoulder that the renderer uses for this avatar, not its latest physics pose.
	var shoulder := _right_shoulder if right else _left_shoulder
	return shoulder.get_global_transform_interpolated().origin


func sleeve_color() -> Color:
	return Color("1c1c1c") if body_type == &"penguin" else shirt_color


## How tall this body type reads relative to the default human build (1.0). Read by
## features/holdables/hand.gd so a penguin's first-person view model sits as low as
## their shortened third-person avatar, without either feature needing to know the
## other's body-type constants.
func height_scale() -> float:
	return _height_scale


func _remote_grounded() -> bool:
	if player.net_velocity.y > 1.0:
		return false
	var feet := player.net_position - Vector3.UP * player.movement.hull_height_m() * 0.5
	var ray := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * 0.12, feet + Vector3.DOWN * 0.18, 1, [player.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit["normal"].y >= 0.7


func _build() -> void:
	_skin_material = _material(skin_color)
	_shirt_material = _material(shirt_color)
	_trim_material = _material(shirt_color.lightened(0.22))
	_pants_material = _material(pants_color)
	_pivot(_rig, self, "Rig", Vector3.ZERO)
	_pivot(_torso, _rig, "Torso", Vector3(0, -0.17, 0))
	_pivot(_head, _torso, "Head", Vector3(0, 0.65, 0))
	_pivot(_left_arm, _torso, "LeftArm", Vector3.ZERO)
	_pivot(_right_arm, _torso, "RightArm", Vector3.ZERO)
	_pivot(_left_shoulder, _torso, "LeftShoulder", Vector3.ZERO)
	_pivot(_right_shoulder, _torso, "RightShoulder", Vector3.ZERO)
	_pivot(_left_leg, _rig, "LeftLeg", Vector3.ZERO)
	_pivot(_right_leg, _rig, "RightLeg", Vector3.ZERO)
	_pivot(_tail, _torso, "Tail", Vector3(0, -0.05, 0.18))
	_decorate()


## (Re)builds every cosmetic box from the current materials and `body_type`, so a
## body type change can reshape the rig without disturbing the pivots animation
## drives (`animate()`) or the paths other features hang onto (`Hand._pose_arms`,
## the GUT tests).
func _decorate() -> void:
	_height_scale = PENGUIN_HEIGHT_SCALE if body_type == &"penguin" else 1.0
	for node: Node3D in [_torso, _head, _left_arm, _right_arm, _left_leg, _right_leg, _tail]:
		_clear_boxes(node)
	if body_type == &"penguin":
		_decorate_penguin()
	else:
		_decorate_humanoid()
	_decorate_tail()
	_apply_clothing()


func _decorate_humanoid() -> void:
	var skin := _skin_material
	var shirt := _shirt_material
	var trim := _trim_material
	var pants := _pants_material
	var underwear := _material(Color("f8f8f1"))
	var feminine := body_type == &"girl"
	var shoulder_width := 0.295 if feminine else 0.335
	var hip_width := 0.145 if feminine else 0.12
	var shirt_size := Vector3(0.40, 0.62, 0.25) if feminine else Vector3(0.46, 0.62, 0.25)
	var trouser_width := 0.25 if feminine else 0.22
	_box(_torso, "Shirt", Vector3(0, 0.31, 0), shirt_size, shirt)
	_box(_torso, "Hem", Vector3(0, 0.028, 0), Vector3(shirt_size.x + 0.008, 0.055, 0.26), trim)
	_box(_torso, "Collar", Vector3(0, 0.59, -0.131), Vector3(0.15, 0.06, 0.012), skin)
	_box(_torso, "Pocket", Vector3(-0.115, 0.41, -0.134), Vector3(0.11, 0.10, 0.014), trim)
	_decorate_head(feminine)
	for side: float in [-1.0, 1.0]:
		var arm := _left_arm if side < 0 else _right_arm
		var leg := _left_leg if side < 0 else _right_leg
		var shoulder := _left_shoulder if side < 0 else _right_shoulder
		arm.position = Vector3(side * shoulder_width, 0.56, 0)
		shoulder.position = arm.position
		_box(arm, "Sleeve", Vector3(0, -0.20, 0), Vector3(0.19, 0.40, 0.24), shirt)
		_box(arm, "Cuff", Vector3(0, -0.39, 0), Vector3(0.195, 0.05, 0.245), trim)
		_box(arm, "Hand", Vector3(0, -0.52, 0), Vector3(0.18, 0.22, 0.23), skin)
		leg.position = Vector3(side * hip_width, -0.17, 0)
		_box(leg, "Trousers", Vector3(0, -0.30, 0), Vector3(trouser_width, 0.60, 0.25), pants)
		_box(
			leg, "Boot", Vector3(0, -0.66, -0.025), Vector3(trouser_width + 0.005, 0.12, 0.30), skin
		)
		_box(
			leg,
			"Underwear",
			Vector3(0, -0.09, 0),
			Vector3(trouser_width + 0.009, 0.19, 0.26),
			underwear
		)


## Builds the head for the current `head_type`, independent of `body_type` so any
## body can wear any head. Not called for the "penguin" body: that costume keeps
## its own fixed head, the same way it ignores clothing (see `_decorate_penguin`).
func _decorate_head(feminine: bool) -> void:
	_head.scale = Vector3.ONE
	match head_type:
		&"frog":
			_decorate_frog_head()
		&"bird":
			_decorate_bird_head()
		_:
			_decorate_human_head(feminine)


func _decorate_human_head(feminine: bool) -> void:
	_head.scale = Vector3(0.76, 0.82, 0.76)
	var skin := _skin_material
	var hair := _material(Color(0.12, 0.075, 0.05))
	var whites := _material(Color(0.92, 0.94, 0.88))
	var eyes := _material(Color(0.12, 0.20, 0.22))
	var hair_back_size := Vector3(0.44, 0.62, 0.025) if feminine else Vector3(0.44, 0.27, 0.025)
	var hair_back_y := 0.06 if feminine else 0.24
	_box(_head, "Face", Vector3(0, 0.19, 0), Vector3(0.43, 0.42, 0.43), skin)
	_box(_head, "HairTop", Vector3(0, 0.405, 0), Vector3(0.45, 0.075, 0.45), hair)
	_box(_head, "HairBack", Vector3(0, hair_back_y, 0.211), hair_back_size, hair)
	_box(_head, "Fringe", Vector3(-0.075, 0.342, -0.22), Vector3(0.29, 0.07, 0.025), hair)
	_box(_head, "FringeLock", Vector3(-0.15, 0.295, -0.22), Vector3(0.085, 0.07, 0.025), hair)
	for side: float in [-1.0, 1.0]:
		_box(_head, "Eye", Vector3(side * 0.105, 0.23, -0.22), Vector3(0.060, 0.035, 0.014), whites)
		_box(_head, "Pupil", Vector3(side * 0.09, 0.23, -0.23), Vector3(0.025, 0.035, 0.01), eyes)
	_box(_head, "Nose", Vector3(0, 0.16, -0.23), Vector3(0.065, 0.055, 0.045), skin)
	_box(_head, "Mouth", Vector3(0, 0.09, -0.22), Vector3(0.095, 0.02, 0.014), hair)


## A wide-mouthed frog head with bulging eyes on top, regardless of skin tone.
func _decorate_frog_head() -> void:
	var skin := _material(Color(0.35, 0.55, 0.20))
	var belly := _material(Color(0.72, 0.80, 0.45))
	var eyes := _material(Color(0.85, 0.85, 0.20))
	var pupils := _material(Color(0.05, 0.05, 0.05))
	_box(_head, "Face", Vector3(0, 0.16, 0), Vector3(0.46, 0.36, 0.46), skin)
	_box(_head, "Snout", Vector3(0, 0.06, -0.235), Vector3(0.30, 0.12, 0.06), belly)
	for side: float in [-1.0, 1.0]:
		_box(_head, "EyeBulge", Vector3(side * 0.15, 0.36, -0.08), Vector3(0.16, 0.16, 0.16), eyes)
		_box(_head, "Pupil", Vector3(side * 0.15, 0.36, -0.16), Vector3(0.06, 0.06, 0.02), pupils)
	_box(_head, "Mouth", Vector3(0, -0.02, -0.235), Vector3(0.34, 0.03, 0.02), pupils)


## A beaked bird head, independent of and visually distinct from the full "penguin"
## body costume so the two can be mixed (a bird head on a human or girl body).
func _decorate_bird_head() -> void:
	var feathers := _material(Color(0.82, 0.62, 0.12))
	var mask := _material(Color(0.96, 0.93, 0.80))
	var beak := _material(Color(0.90, 0.45, 0.08))
	var eyes := _material(Color(0.05, 0.05, 0.05))
	_box(_head, "Face", Vector3(0, 0.19, 0), Vector3(0.40, 0.38, 0.40), feathers)
	_box(_head, "FaceMask", Vector3(0, 0.11, -0.15), Vector3(0.22, 0.18, 0.10), mask)
	_box(_head, "Beak", Vector3(0, 0.15, -0.25), Vector3(0.11, 0.08, 0.13), beak)
	for side: float in [-1.0, 1.0]:
		_box(_head, "Eye", Vector3(side * 0.10, 0.27, -0.20), Vector3(0.06, 0.06, 0.01), eyes)


## Attaches the current `tail_type` behind the hips, on any body type (including
## "penguin") since it's a small additive accessory, not a full costume.
func _decorate_tail() -> void:
	match tail_type:
		&"lizard":
			_decorate_lizard_tail()
		&"fin":
			_decorate_fin_tail()
		&"fluffy":
			_decorate_fluffy_tail()


## A tapering row of scaly segments.
func _decorate_lizard_tail() -> void:
	var scales := _material(Color(0.30, 0.55, 0.25))
	var sizes: Array[Vector3] = [
		Vector3(0.16, 0.16, 0.22),
		Vector3(0.13, 0.13, 0.20),
		Vector3(0.09, 0.09, 0.18),
		Vector3(0.05, 0.05, 0.14),
	]
	var z := 0.0
	var y := 0.0
	for index: int in sizes.size():
		var size: Vector3 = sizes[index]
		z += size.z * 0.5
		_box(_tail, "Segment%d" % index, Vector3(0, y, z), size, scales)
		z += size.z * 0.5
		y -= 0.02


## A flat, fanned fish tail.
func _decorate_fin_tail() -> void:
	var fin := _material(Color(0.20, 0.45, 0.65))
	_box(_tail, "Base", Vector3(0, 0, 0.08), Vector3(0.10, 0.10, 0.16), fin)
	_box(_tail, "Fan", Vector3(0, 0, 0.22), Vector3(0.32, 0.22, 0.03), fin)


## A round, puffy fur tail.
func _decorate_fluffy_tail() -> void:
	var fur := _material(Color(0.55, 0.40, 0.25))
	_box(_tail, "Puff", Vector3(0, 0.02, 0.11), Vector3(0.22, 0.22, 0.22), fur)
	_box(_tail, "PuffTip", Vector3(0, 0.05, 0.25), Vector3(0.15, 0.15, 0.15), fur)


## A short, rounded penguin costume: black feathers, a white belly, an orange beak
## and feet, and stubby flipper arms. Ignores clothing entirely (see the early
## return in `_apply_clothing`) since it's a full-body costume, not an outfit.
func _decorate_penguin() -> void:
	_head.scale = Vector3.ONE
	var feathers := _material(Color("1c1c1c"))
	var belly := _material(Color("f5f5f0"))
	var beak := _material(Color("e8891c"))
	var eyes := _material(Color(0.05, 0.05, 0.05))
	_box(_torso, "Body", Vector3(0, 0.30, 0), Vector3(0.42, 0.58, 0.34), feathers)
	_box(_torso, "Belly", Vector3(0, 0.22, -0.10), Vector3(0.28, 0.42, 0.20), belly)
	_box(_head, "Face", Vector3(0, 0.19, 0), Vector3(0.36, 0.34, 0.36), feathers)
	_box(_head, "FaceMask", Vector3(0, 0.11, -0.14), Vector3(0.20, 0.16, 0.10), belly)
	_box(_head, "Beak", Vector3(0, 0.15, -0.23), Vector3(0.10, 0.07, 0.12), beak)
	for side: float in [-1.0, 1.0]:
		_box(_head, "Eye", Vector3(side * 0.09, 0.26, -0.19), Vector3(0.055, 0.055, 0.01), eyes)
	for side: float in [-1.0, 1.0]:
		var arm := _left_arm if side < 0 else _right_arm
		var leg := _left_leg if side < 0 else _right_leg
		var shoulder := _left_shoulder if side < 0 else _right_shoulder
		arm.position = Vector3(side * 0.24, 0.44, 0)
		shoulder.position = arm.position
		_box(arm, "Flipper", Vector3(0, -0.19, 0), Vector3(0.09, 0.38, 0.16), feathers)
		leg.position = Vector3(side * 0.10, -0.17, 0)
		_box(leg, "Foot", Vector3(0, -0.30, 0.06), Vector3(0.15, 0.10, 0.26), beak)


func _clear_boxes(node: Node3D) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			node.remove_child(child)
			child.queue_free()


func _pivot(node: Node3D, parent: Node3D, label: String, at: Vector3) -> void:
	node.name = label
	node.position = at
	parent.add_child(node)


func _box(
	parent: Node3D, label: String, at: Vector3, dimensions: Vector3, material: Material
) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	if label in ["Shirt", "Trousers", "Face"] and body_type != &"penguin":
		part.mesh = _tapered_mesh(mesh, 0.82 if label == "Shirt" else 0.9)
	part.material_override = material
	part.position = at
	parent.add_child(part)


func _tapered_mesh(box: BoxMesh, lower_width: float) -> ArrayMesh:
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index: int in vertices.size():
		if vertices[index].y < 0.0:
			vertices[index].x *= lower_width
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var builder := SurfaceTool.new()
	builder.create_from(mesh, 0)
	builder.deindex()
	builder.generate_normals()
	return builder.commit()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return material


func set_clothing(new_shirt: String, new_pants: String) -> void:
	if new_shirt == shirt_id and new_pants == pants_id:
		return
	shirt_id = new_shirt if ClothingCatalog.slot(new_shirt) == "shirt" else ""
	pants_id = new_pants if ClothingCatalog.slot(new_pants) == "pants" else ""
	if _shirt_material != null:
		_apply_clothing()


func _apply_clothing() -> void:
	# The penguin costume has no Hem/Pocket/Cuff/Underwear boxes to recolor or
	# toggle, and always wears its own feathers regardless of equipped clothing.
	if body_type == &"penguin":
		return
	shirt_color = skin_color if shirt_id.is_empty() else ClothingCatalog.color(shirt_id)
	pants_color = skin_color if pants_id.is_empty() else ClothingCatalog.color(pants_id)
	_shirt_material.albedo_color = shirt_color
	_trim_material.albedo_color = shirt_color.lightened(0.22)
	_pants_material.albedo_color = pants_color
	for part: String in ["Hem", "Pocket"]:
		(_torso.get_node(part) as Node3D).visible = not shirt_id.is_empty()
	for arm: Node3D in [_left_arm, _right_arm]:
		(arm.get_node("Cuff") as Node3D).visible = not shirt_id.is_empty()
	for leg: Node3D in [_left_leg, _right_leg]:
		(leg.get_node("Underwear") as Node3D).visible = pants_id.is_empty()


## "girl" narrows the shoulders and waist, widens the hips and grows the hair out.
## "penguin" replaces the build with a short penguin costume (see `_decorate_penguin`).
## Anything else (including an unrecognized value) is the original "default" build.
func set_body_type(new_type: String) -> void:
	var next: StringName = &"default"
	if new_type == "girl":
		next = &"girl"
	elif new_type == "penguin":
		next = &"penguin"
	if next == body_type:
		return
	body_type = next
	if _skin_material != null:
		_decorate()


## "frog" and "bird" reshape the head (see `_decorate_head`). Anything else
## (including an unrecognized value) keeps the original human head. Has no effect
## while `body_type` is "penguin", which keeps its own fixed head.
func set_head_type(new_type: String) -> void:
	var next: StringName = &"human"
	if new_type == "frog":
		next = &"frog"
	elif new_type == "bird":
		next = &"bird"
	if next == head_type:
		return
	head_type = next
	if _skin_material != null:
		_decorate()


## "lizard", "fin" and "fluffy" attach a tail behind the hips. Anything else
## (including an unrecognized value) has no tail.
func set_tail_type(new_type: String) -> void:
	var next: StringName = &"none"
	if new_type == "lizard":
		next = &"lizard"
	elif new_type == "fin":
		next = &"fin"
	elif new_type == "fluffy":
		next = &"fluffy"
	if next == tail_type:
		return
	tail_type = next
	if _skin_material != null:
		_decorate()


func set_skin_index(index: int) -> void:
	var next := PlayerSkin.TONES[clampi(index, 0, PlayerSkin.TONES.size() - 1)]
	if next == skin_color:
		return
	skin_color = next
	if _skin_material != null:
		_skin_material.albedo_color = skin_color
		_apply_clothing()
