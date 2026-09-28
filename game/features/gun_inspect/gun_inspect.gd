extends Node
## Local input/mount adapter. All pose curves, timing and playback state live in Rust.

const ACTION := &"inspect_weapon"

var _animation := WeaponInspect.new()
var _owner: Node3D
var _weapon := ""
var _identity := ""


func _ready() -> void:
	# After camera selection (10), before Hand and GunRig position their mounts (20).
	process_priority = 15
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	Controls.ensure_action(ACTION, [key])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and try_inspect():
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Cancel before weapon input handlers run, including input they mark handled.
	for action: StringName in [&"primary_action", &"gun_fire", &"gun_reload", &"drop_item"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			cancel()
			return


func _process(delta: float) -> void:
	_sync_weapon()
	if not _can_inspect():
		cancel()
		return
	_owner.set("inspect_transform", _animation.advance(delta))


func try_inspect() -> bool:
	_sync_weapon()
	return _can_inspect() and _animation.start(_weapon)


func cancel() -> void:
	_animation.cancel()
	if is_instance_valid(_owner):
		_owner.set("inspect_transform", Transform3D.IDENTITY)


func _exit_tree() -> void:
	cancel()


func _can_inspect() -> bool:
	if not is_instance_valid(_owner) or not Controls.gameplay_active():
		return false
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or player.is_queued_for_deletion():
		return false
	if (player.get_node("Body") as Node3D).visible:
		return false
	for action: StringName in [&"primary_action", &"gun_fire", &"gun_reload"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return false
	return bool(_owner.call("can_inspect"))


func _sync_weapon() -> void:
	var peer := multiplayer.get_unique_id()
	var next_owner: Node3D
	var next_weapon := ""
	var rig := GunRig.for_peer(get_tree(), peer)
	var hand := Hand.for_peer(get_tree(), peer)
	if rig != null and rig.is_active():
		next_owner = rig
		next_weapon = "generated:%d" % int(rig.net_stats["ammo_type"])
	elif hand != null:
		var definition := ItemCatalog.find(hand.net_item_id)
		if definition != null and definition.category == ItemDefinition.Category.WEAPON:
			next_owner = hand
			next_weapon = hand.net_item_id
	# Different rolls of the same ammo family must cancel too.
	var identity := (
		JSON.stringify(rig.net_stats) if next_owner == rig and rig != null else next_weapon
	)
	if next_owner != _owner or identity != _identity:
		cancel()
		_owner = next_owner
		_weapon = next_weapon
		_identity = identity
