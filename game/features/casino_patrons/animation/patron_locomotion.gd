extends RefCounted
## Shared in-place bone clips; each patron owns its blend state and playback clock.

const CLIPS := preload("res://assets/casino_patrons/animations/locomotion.tres")
const Bisect := preload("res://features/profiler/animation_bisect.gd")

var avatar: BlockPlayerModel
var tree := AnimationTree.new()
var _blend := 0.0
var _initialized := false
var _fingers_enabled := true
var _cycle_length := CLIPS.get_animation(&"walk").length
var _full_swing := lerpf(0.3, 0.95, PatronMath.WALK_SPEED / PatronModel.RIG_MAX_SPEED)


func _init(model: BlockPlayerModel) -> void:
	avatar = model
	var player := AnimationPlayer.new()
	player.name = "PatronClips"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library(&"", CLIPS)
	avatar.add_child(player)
	var graph := AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	var walk := AnimationNodeAnimation.new()
	walk.animation = &"walk"
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	graph.add_node(&"Idle", idle)
	graph.add_node(&"Walk", walk)
	graph.add_node(&"Locomotion", blend)
	graph.add_node(&"Seek", AnimationNodeTimeSeek.new())
	graph.connect_node(&"Locomotion", 0, &"Idle")
	graph.connect_node(&"Locomotion", 1, &"Walk")
	graph.connect_node(&"Seek", 0, &"Locomotion")
	graph.connect_node(&"output", 0, &"Seek")
	tree.name = "PatronAnimation"
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	avatar.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.active = true


func pose(delta: float, walk: float, flinch: float, idle: float) -> void:
	avatar.seated = false
	var speed := walk * PatronMath.WALK_SPEED
	var moving := speed >= BlockPlayerMotion.IDLE_SPEED
	var weight := 0.0
	if moving:
		weight = lerpf(0.3, 0.95, speed / PatronModel.RIG_MAX_SPEED) / _full_swing
	_blend = lerpf(_blend, weight, 1.0 - exp(-14.0 * delta))
	avatar.locomotion = &"walk" if moving else &"idle"
	var step := BlockPlayerMotion.phase_step(speed, PatronModel.RIG_MAX_SPEED, delta) / TAU
	avatar._phase = fmod(avatar._phase + step * TAU, TAU)
	avatar._head.rotation = Vector3(flinch * 0.5, sin(idle * 0.7) * 0.5 * (1.0 - walk), 0)
	if not Bisect.skeleton:
		_initialized = false
		return
	if not _initialized:
		avatar.human.pose(avatar, false, false)
		tree.set("parameters/Seek/seek_request", avatar._phase / TAU * _cycle_length)
		_initialized = true
		_fingers_enabled = Bisect.fingers
		step = 0.0
	if _fingers_enabled != Bisect.fingers:
		_fingers_enabled = Bisect.fingers
		avatar.human.set_finger_curl(false, 0.12)
		avatar.human.set_finger_curl(true, 0.12)
	tree.active = true
	tree.set("parameters/Locomotion/blend_amount", _blend)
	tree.advance(step * _cycle_length)
	# Head turning/flinching is a targeted overlay, never another full-body pass.
	avatar.human._bone("Head", avatar._head.rotation)


func suspend() -> void:
	tree.active = false
	_initialized = false
