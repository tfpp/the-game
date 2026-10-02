class_name BoxingKicks
extends Node3D
## Transient accepted kick poses; local charge is cosmetic and never supplies damage.

const QUICK_S := 0.3
const POWER_S := 0.45

var _left: Dictionary[int, float] = {}
var _power: Dictionary[int, bool] = {}
var _views: Dictionary[int, Node3D] = {}
var _local_charge := -1.0


func _ready() -> void:
	top_level = true
	process_priority = 24


func set_local_charge(charge: float) -> void:
	_local_charge = charge


func swing(peer: int, power: bool) -> void:
	_left[peer] = POWER_S if power else QUICK_S
	_power[peer] = power


func leg_pose(peer: int) -> Dictionary:
	if not _left.has(peer):
		return {}
	var total := POWER_S if _power[peer] else QUICK_S
	return pose_at(1.0 - _left[peer] / total)


static func pose_at(t: float) -> Dictionary:
	var extension := BoxingFists.swing_reach(t) / 0.45
	# Positive X lifts a downward leg toward forward (-Z); the knee unfolds.
	return {"thigh": lerpf(0.45, PI * 0.5, extension), "shin": lerpf(-1.1, -0.08, extension)}


func forget_peer(peer: int) -> void:
	_left.erase(peer)
	_power.erase(peer)
	if _views.has(peer):
		_views[peer].queue_free()
		_views.erase(peer)


func reset() -> void:
	for peer: int in _views.keys():
		forget_peer(peer)
	_left.clear()
	_power.clear()
	_local_charge = -1.0


func _process(delta: float) -> void:
	for peer: int in _left.keys():
		_left[peer] -= delta
		if _left[peer] <= 0.0:
			_left.erase(peer)
			_power.erase(peer)
	var me := multiplayer.get_unique_id()
	for peer: int in _views.keys():
		if _player_for(peer) == null:
			forget_peer(peer)
		else:
			_views[peer].hide()
	# Remote/third-person kicks use the avatar, not a second surface.
	if _left.has(me):
		_pose(me, leg_pose(me))
	elif _local_charge >= 0.0:
		_pose(me, {"thigh": 0.45 + _local_charge * 0.35, "shin": -1.1})


func _pose(peer: int, pose: Dictionary) -> void:
	var player := _player_for(peer)
	if player == null or (player.get_node("Body") as Node3D).visible:
		return
	var avatar := player.get_node_or_null("Body/Avatar") as BlockPlayerModel
	if avatar == null:
		return
	var view := _view_for(peer)
	view.show()
	var camera := player.get_node("Camera") as Camera3D
	view.global_transform = camera.global_transform
	var human := view.get_node("Leg") as SkinnedHuman
	var penguin := view.get_node_or_null("Penguin") as Node3D
	human.visible = avatar.body_type != &"penguin"
	if human.visible:
		if penguin != null:
			penguin.hide()
		human.apply_appearance(avatar)
		human.pose(avatar, false, false)
		human.material.set_shader_parameter("right_leg_only", true)
		human._bone("ThighR", Vector3(float(pose["thigh"]), 0, 0))
		human._bone("CalfR", Vector3(float(pose["shin"]), 0, 0))
		human.position = Vector3(0.06, -0.25, -0.25) * avatar.height_scale()
		human.scale = Vector3.ONE * avatar.height_scale()
	else:
		if penguin == null:
			# Reuse the existing penguin leg geometry/materials, not a human boot.
			penguin = avatar._right_leg.duplicate() as Node3D
			penguin.name = "Penguin"
			view.add_child(penguin)
		penguin.show()
		penguin.position = Vector3(0.15, -0.22, -0.45) * avatar.height_scale()
		penguin.scale = Vector3.ONE * avatar.height_scale()
		penguin.rotation.x = pose["thigh"]


func _view_for(peer: int) -> Node3D:
	if _views.has(peer):
		return _views[peer]
	var view := Node3D.new()
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	var human := SkinnedHuman.new()
	human.name = "Leg"
	view.add_child(human)
	_views[peer] = view
	return view


func _player_for(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if (
			player != null
			and player.multiplayer == multiplayer
			and player.get_multiplayer_authority() == peer
		):
			return player
	return null
