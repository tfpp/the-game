class_name BoxingFists
extends Node3D
## Cosmetic fists for features/boxing: a pair of bare fists held in front of each
## punching player's eyes. They appear while the local player winds up a power
## punch (drawn back and shaking harder as it charges) and on every peer while
## anyone throws a punch, then hide again, so an unarmed player isn't stuck with
## fists covering the view.

const SWING_S := 0.22
const POWER_SWING_S := 0.35

## peer -> seconds left in that peer's swing, and whether it's a power punch.
var _swing_left: Dictionary[int, float] = {}
var _swing_power: Dictionary[int, bool] = {}
var _views: Dictionary[int, Node3D] = {}
var _local_charge := -1.0


func _ready() -> void:
	top_level = true
	process_priority = 24


## -1 hides the local wind-up; 0..1 shows the fists drawn back by that charge.
func set_local_charge(charge: float) -> void:
	_local_charge = charge


## Read-only presentation shared with the avatar; only accepted server swings enter here.
func arm_pose(peer: int) -> Dictionary:
	if not _swing_left.has(peer):
		return {}
	var power := _swing_power[peer]
	var total := POWER_SWING_S if power else SWING_S
	return {"power": power, "reach": swing_reach(1.0 - _swing_left[peer] / total)}


func forget_peer(peer: int) -> void:
	_swing_left.erase(peer)
	_swing_power.erase(peer)
	if _views.has(peer):
		_views[peer].queue_free()
		_views.erase(peer)


func reset() -> void:
	for peer: int in _views.keys():
		forget_peer(peer)
	_swing_left.clear()
	_swing_power.clear()
	_local_charge = -1.0


func swing(peer: int, power: bool) -> void:
	_swing_left[peer] = POWER_SWING_S if power else SWING_S
	_swing_power[peer] = power


func _process(delta: float) -> void:
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for peer: int in _swing_left.keys():
		_swing_left[peer] -= delta
		if _swing_left[peer] <= 0.0:
			_swing_left.erase(peer)
			_swing_power.erase(peer)
	for peer: int in _views.keys():
		if _player_for(peer) == null:
			_views[peer].queue_free()
			_views.erase(peer)
		elif not _swing_left.has(peer) and not (peer == me and _local_charge >= 0.0):
			_views[peer].visible = false
	for peer: int in _swing_left.keys():
		var total := POWER_SWING_S if _swing_power[peer] else SWING_S
		_pose(peer, swing_reach(1.0 - _swing_left[peer] / total), _swing_power[peer])
	if _local_charge >= 0.0 and not _swing_left.has(me):
		_pose(me, -0.25 * _local_charge, true)


## How far forward the punching fist is (in metres, negative = drawn back) at
## `t` (0..1) through a swing: a fast snap out, then an easier pull back.
static func swing_reach(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	if clamped < 0.35:
		return 0.45 * clamped / 0.35
	return 0.45 * (1.0 - (clamped - 0.35) / 0.65)


func _pose(peer: int, reach: float, power: bool) -> void:
	var player := _player_for(peer)
	var view := _view_for(peer)
	if player == null:
		view.visible = false
		return
	# The world avatar supplies remote and third-person arms.
	view.visible = player.is_local() and not (player.get_node("Body") as Node3D).visible
	if not view.visible:
		return
	var avatar := player.get_node_or_null("Body/Avatar") as BlockPlayerModel
	if avatar == null:
		view.hide()
		return
	var camera := player.get_node("Camera") as Camera3D
	view.global_transform = camera.global_transform
	var human := view.get_node("Hands") as SkinnedHuman
	human.apply_appearance(avatar)
	human.pose(avatar, false, false)
	human.material.set_shader_parameter("arms_only", true)
	human.material.set_shader_parameter("shirt_tint", avatar.sleeve_color())
	var shake := 0.0
	if peer == multiplayer.get_unique_id() and _local_charge >= 0.0:
		shake = sin(Time.get_ticks_msec() * 0.06) * 0.008 * _local_charge
	# Camera-space wrists point down -Z; IK keeps elbows connected to shoulders.
	var drop := -0.36 * avatar.height_scale()
	for right: bool in [false, true]:
		var side := 1.0 if right else -1.0
		var lead := right == power
		human.place_shoulder(right, view.to_global(Vector3(side * 0.28, drop, 0.05)))
		var wrist := Vector3(side * 0.2, drop + 0.16, -0.4)
		if lead:
			wrist.z -= reach
			wrist.y += shake
		human.reach_grip(right, view.to_global(wrist), true)
		human.orient_grip(right, view.global_basis)
		human.set_finger_curl(right, 1.0)


func _view_for(peer: int) -> Node3D:
	if _views.has(peer):
		return _views[peer]
	var view := Node3D.new()
	view.name = "Fists%d" % peer
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(view)
	var human := SkinnedHuman.new()
	human.name = "Hands"
	view.add_child(human)
	_views[peer] = view
	return view


func _player_for(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer):
			return player
	return null
