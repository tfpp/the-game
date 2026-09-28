extends Node3D
## A line of gnomes that dash single file, train-style, between two holes the size of
## dog doors, over and over.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) drives `net_progress`/`net_forward` in
## `_physics_process`, replicated to every client by Sync (MultiplayerSynchronizer).
## Every peer derives each gnome's position independently from that shared state plus
## the tunnel's two hole positions, which are fixed in the scene and therefore already
## identical everywhere. GnomeMath.follower_distance gives the single-file spacing.

const REMOTE_SMOOTHING := 12.0

## Replicated state (server -> everyone). See the synchronizer config in gnome_train.tscn.
@export var net_progress := 0.0
@export var net_forward := true

var _hole_a := Vector3.ZERO
var _hole_b := Vector3.ZERO
var _path_length := 0.0
var _total_distance := 0.0
var _resting := true
var _rest_timer := 0.0
var _smoothed: Array[Vector3] = []
var _smoothed_yaw: Array[float] = []

@onready var _gnomes: Array[Node3D] = [$Gnome0, $Gnome1, $Gnome2, $Gnome3]


func _ready() -> void:
	_hole_a = $HoleA.position
	_hole_b = $HoleB.position
	_path_length = _hole_a.distance_to(_hole_b)
	_total_distance = GnomeMath.total_distance(
		_path_length, _gnomes.size(), GnomeMath.FOLLOW_SPACING
	)
	for i in _gnomes.size():
		_smoothed.append(_hole_a)
		_smoothed_yaw.append(0.0)
	if multiplayer.is_server():
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _resting:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_resting = false
			net_progress = 0.0
		return
	var duration := GnomeMath.leg_duration(_total_distance, GnomeMath.RUN_SPEED)
	net_progress = GnomeMath.advance_progress(net_progress, delta, duration)
	if net_progress >= 1.0:
		_resting = true
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
		net_forward = not net_forward


func _process(delta: float) -> void:
	var yaw := GnomeMath.facing_yaw(_hole_a, _hole_b, net_forward)
	var is_server := multiplayer.is_server()
	var lerp_t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	for i in _gnomes.size():
		var distance := GnomeMath.follower_distance(
			net_progress, _total_distance, _path_length, i, GnomeMath.FOLLOW_SPACING
		)
		var target := GnomeMath.gnome_position(
			_hole_a, _hole_b, net_forward, distance, _path_length
		)
		var gnome := _gnomes[i]
		if is_server:
			gnome.position = target
			gnome.rotation.y = yaw
		else:
			_smoothed[i] = _smoothed[i].lerp(target, lerp_t)
			_smoothed_yaw[i] = lerp_angle(_smoothed_yaw[i], yaw, lerp_t)
			gnome.position = _smoothed[i]
			gnome.rotation.y = _smoothed_yaw[i]
		gnome.visible = GnomeMath.gnome_visible(distance, _path_length)
