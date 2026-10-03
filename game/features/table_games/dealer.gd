class_name CrownDealer
extends Node3D
## Shared authored full-body clips. Round snapshot supplies queue and elapsed time.
const CLIPS := preload("res://assets/table_games/animations/dealer.res")
const DECK := preload("res://assets/casino_props/models/card_deck.res")
const DECK_MATERIAL := preload("res://features/casino_props/materials/card_deck.tres")
const TUX := preload("res://assets/casino_patrons/textures/dealer_tux.png")
@export var preview_on_server := false
var table: CrownGameTable
var model: BlockPlayerModel
var animation: AnimationPlayer
var current_motion := "idle"
var _deck: Node3D
var _card: Node3D
var _chips: Node3D
var _dice: Node3D
var _serial := -1
var _elapsed := 0.0
var _snapshot_elapsed := -1.0
var _queue: Array = []
var _idle_time := 0.0


func _ready() -> void:
	table = get_parent() as CrownGameTable
	if table.game == "video_poker":
		set_process(false)
		return
	var visual := table.get_node_or_null("Model") as MeshInstance3D
	var bounds := (
		visual.mesh.get_aabb()
		if visual != null
		else AABB(Vector3(-1.3, 0, -.7), Vector3(2.6, 1, 1.4))
	)
	position = Vector3(0, 0, bounds.position.z - .37)
	if DisplayServer.get_name() == "headless" and not preview_on_server:
		set_process(false)
		return
	model = BlockPlayerModel.new()
	model.name = "Avatar"
	model.position.y = .9144
	model.rotation.y = PI
	add_child(model)
	model.set_appearance(
		{"skin": 3, "hair": "crop", "hair_color": 0, "eyes": 0, "outfit": "casual"}
	)
	model.human.material.set_shader_parameter("tux_texture", TUX)
	model.human.material.set_shader_parameter("tuxedo", true)
	model.human.material.set_shader_parameter("pants_equipped", true)
	model.human.material.set_shader_parameter("pants_tint", Color("1d1d22"))
	model.animate(0, Vector3.ZERO, true, 1)
	animation = AnimationPlayer.new()
	animation.name = "DealerClips"
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.add_animation_library(&"", CLIPS)
	model.add_child(animation)
	animation.play(&"idle")
	animation.advance(0)
	_deck = _hand_prop(false, DECK, DECK_MATERIAL)
	_card = _hand_prop(true, DECK, DECK_MATERIAL)
	_card.scale = Vector3(.8, .08, .8)
	_chips = _hand_prop(
		false,
		preload("res://assets/casino_props/models/chip_stack.res"),
		preload("res://features/casino_props/materials/chip_stack.tres")
	)
	_dice = _hand_prop(
		true,
		preload("res://assets/casino_props/models/craps_dice.res"),
		preload("res://features/casino_props/materials/craps_dice.tres")
	)
	_show_props()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or animation == null:
		return
	var camera := get_viewport().get_camera_3d()
	if (
		not preview_on_server
		and camera != null
		and global_position.distance_squared_to(camera.global_position) > 400
	):
		return
	var cue: Dictionary = table.state.get("dealer_animation", {})
	var serial := int(cue.get("serial", 0))
	var received := float(cue.get("elapsed", 0.0))
	if serial != _serial:
		_serial = serial
		_queue = cue.get("queue", []).duplicate()
		_elapsed = received
		_snapshot_elapsed = received
	elif not is_equal_approx(received, _snapshot_elapsed):
		_elapsed = received
		_snapshot_elapsed = received
	else:
		_elapsed += delta
	_idle_time += delta
	var moment := _elapsed
	var motion := "idle"
	for clip: String in _queue:
		var length := CLIPS.get_animation(StringName(clip)).length
		if moment < length - .0001:
			motion = clip
			break
		moment -= length
	current_motion = motion
	_show_props()
	if str(animation.current_animation) != motion:
		animation.play(StringName(motion))
	animation.seek(fposmod(_idle_time, 4) if motion == "idle" else moment, true)
	animation.advance(0)


func _hand_prop(right: bool, mesh: ArrayMesh, material: Material) -> MeshInstance3D:
	var mount := BoneAttachment3D.new()
	mount.bone_name = "HandR" if right else "HandL"
	model.human.skeleton.add_child(mount)
	var prop := MeshInstance3D.new()
	prop.mesh = mesh
	prop.material_override = material
	prop.position = Vector3(0, .04, .02)
	mount.add_child(prop)
	return prop


func _show_props() -> void:
	if _deck == null:
		return
	_deck.visible = table.game != "craps" and ["shuffle", "deal"].has(current_motion)
	_card.visible = (
		table.game != "craps" and ["shuffle", "deal", "reveal", "collect"].has(current_motion)
	)
	_chips.visible = current_motion == "payout"
	_dice.visible = table.game == "craps" and current_motion == "roll"
