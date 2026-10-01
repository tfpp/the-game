class_name Hand
extends Node3D
## One player's held item: what they're holding, and where its visual sits, for
## everyone watching. Spawned by the holdables feature (holdables.gd) as a companion
## of the matching Player, since core/player isn't ours to edit — see
## `_mount_transform` for how it tracks the player without being parented to it.
##
## Holding is server-authoritative like the rest of shared state (game/AGENTS.md), so
## unlike Player's client-authoritative movement this keeps the default multiplayer
## authority (1, the server). Clients only ever request an action; the server decides.

## Emitted whenever this hand's weapon fires. `_play_fire` broadcasts to every peer
## (see its `@rpc` annotation), so this fires identically for everyone watching, not
## just the shooter — features/weapon_hotbar's recoil animation listens for it
## without hand.gd needing to know that feature exists.
signal fired(item_id: String)

const THROW_DISTANCE := 5.0
const DROP_DISTANCE := 1.2
const HITSCAN_RANGE_M := 50.0
const FLASH_DURATION_S := 0.06

## Replicated (server -> everyone). See the synchronizer config in hand.tscn.
@export var net_item_id := ""

## Set from spawn data (see holdables.gd), identically on every peer, before this node
## enters the tree, so it doesn't need its own synchronizer property.
var peer_id := 0
## Derived by the server from the account ID (or peer ID in offline/dev play).
var skin_index := -1

var _mounted_item_id := ""
var _view: Node3D
var _arms := HeldArms.new()
var _flash_timer := 0.0
var _fire_cooldown := 0.0

@onready var consumption: ConsumableUse = $Consumption

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	# Player updates at priority 0; third-person camera updates at 10.
	process_priority = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arms.name = "Arms"
	add_child(_arms)
	add_to_group(&"hands")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	Controls.ensure_action(&"primary_action", [mouse, pad])
	var drop_key := InputEventKey.new()
	drop_key.physical_keycode = KEY_G
	var drop_pad := InputEventJoypadButton.new()
	drop_pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	Controls.ensure_action(&"drop_item", [drop_key, drop_pad])
	_rebuild_view()


func _process(delta: float) -> void:
	consumption.advance(delta)
	if consumption.view_id() != _mounted_item_id:
		_rebuild_view()
	if _view != null:
		var smoke := _view.get_node_or_null("Smoke") as CPUParticles3D
		if smoke != null:
			smoke.emitting = consumption.active()
	var player := _player()
	visible = player != null and not consumption.view_id().is_empty()
	if player != null:
		global_transform = consumption.pose(player, _mount_transform(player))
		_pose_arms(player)
		consumption.pose_fingers(player)
		var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
		if models != null and models.emote_elapsed(peer_id) >= 0.0:
			_arms.human.material.set_shader_parameter("hide_left_arm", true)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_set_flash(false)
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id() or not Controls.gameplay_active():
		return
	if net_item_id.is_empty():
		return
	if event.is_action_pressed(&"primary_action"):
		request_primary_action.rpc_id(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"drop_item"):
		request_drop_item.rpc_id(1)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func request_primary_action() -> void:
	if not multiplayer.is_server() or not _is_own_request():
		return
	if consumption.active():
		return
	if ItemCatalog.uses_remaining(net_item_id) > 0:
		consumption.entity.receive_legacy_action(&"consume")
		return
	var def := ItemCatalog.find(net_item_id)
	if def == null:
		return
	match def.category:
		ItemDefinition.Category.WEAPON:
			_fire(def)
		ItemDefinition.Category.FOOD:
			_eat(def)
		ItemDefinition.Category.PROP:
			_throw(def)


## Drops whatever is held, regardless of category, a short toss in front of the
## player. Inventory storage and swapping provide the other ways to free a hand.
@rpc("any_peer", "call_local", "reliable")
func request_drop_item() -> void:
	if consumption.active():
		return
	if not multiplayer.is_server() or not _is_own_request() or net_item_id.is_empty():
		return
	var def := ItemCatalog.find(net_item_id)
	if def != null:
		_toss(def, DROP_DISTANCE)


## Server: hands this an item, if it's empty. Called by pickups and landed throws.
func try_equip(item_id: String) -> bool:
	if not multiplayer.is_server() or not net_item_id.is_empty():
		return false
	if ItemCatalog.find(item_id) == null or not ClothingCatalog.slot(item_id).is_empty():
		return false
	net_item_id = item_id
	return true


## A Hand tracks its owner by peer id (see `peer_id`), not scene position, so any
## script holding a `Player` can find its hand this way.
static func for_peer(tree: SceneTree, target_peer_id: int) -> Hand:
	for node: Node in tree.get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand != null and hand.peer_id == target_peer_id:
			return hand
	return null


func _is_own_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	var effective := sender if sender != 0 else multiplayer.get_unique_id()
	return effective == peer_id


func _fire(def: ItemDefinition) -> void:
	if _fire_cooldown > 0.0:
		return
	var player := _player()
	if player == null:
		return
	_fire_cooldown = def.fire_cooldown_s
	var origin := _aim_origin(player)
	_play_fire.rpc(def.id, origin)
	if def.damage <= 0.0:
		return
	var combat := get_tree().get_first_node_in_group(&"combat")
	var played_impact := false
	for _pellet: int in maxi(def.pellet_count, 1):
		var jitter := deg_to_rad(def.spread_degrees)
		var yaw := player.net_yaw + randf_range(-jitter, jitter)
		var pitch := clampf(
			player.net_pitch + randf_range(-jitter, jitter), deg_to_rad(-89.0), deg_to_rad(89.0)
		)
		var hit := _hitscan(player, origin, ThrowMath.aim_direction(yaw, pitch))
		if hit.is_empty():
			continue
		var target := hit["collider"] as Node3D
		if target == null:
			continue
		if not played_impact:
			_play_impact.rpc(hit["position"], target is Player or target.is_in_group(&"killable"))
			played_impact = true
		var target_player := target as Player
		if target_player != null and combat != null:
			combat.call(
				"apply_damage", target_player.get_multiplayer_authority(), def.damage, peer_id
			)
		elif target_player == null and target.is_in_group(&"killable"):
			target.call("take_hit", peer_id)


## Keep the hit position for spatial impact audio, alongside the damage target.
func _hitscan(shooter: Player, origin: Vector3, direction: Vector3) -> Dictionary:
	# Layer 2 lets shots hit small wildlife without blocking player movement.
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * HITSCAN_RANGE_M, 1 | 2, [shooter.get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(query)


@rpc("authority", "call_local", "reliable")
func _play_fire(item_id: String, origin: Vector3) -> void:
	_flash_timer = FLASH_DURATION_S
	_set_flash(true)
	fired.emit(item_id)
	# Use the event's weapon ID; replicated equipment may already have changed.
	GameAudio.play_at(self, StringName(item_id), origin)


@rpc("authority", "call_local", "reliable")
func _play_impact(at: Vector3, living: bool) -> void:
	GameAudio.play_at(self, &"hit" if living else &"impact", at)


## Only the collecting/equipping owner hears inventory confirmations.
@rpc("authority", "call_local", "reliable")
func _play_inventory(cue: StringName) -> void:
	if peer_id == multiplayer.get_unique_id():
		GameAudio.play_ui(self, cue)


func _eat(def: ItemDefinition) -> void:
	net_item_id = ""
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat != null and def.heal_amount > 0.0:
		combat.call("heal", peer_id, def.heal_amount)
	_play_eaten.rpc(def.id)


## An event, not saved state: late joiners don't need to replay an old bite.
@rpc("authority", "call_local", "reliable")
func _play_eaten(_item_id: String) -> void:
	pass


func _throw(def: ItemDefinition) -> void:
	_toss(def, THROW_DISTANCE)


## Empties the hand and asks holdables to spawn `def` on the ground `distance` ahead
## of where the player's looking — a full throw for a PROP's primary action, or a
## short toss for a plain drop (see `_throw` and `request_drop_item`).
func _toss(def: ItemDefinition, distance: float) -> void:
	var player := _player()
	if player == null:
		net_item_id = ""
		return
	net_item_id = ""
	var from := (
		HeldItemPose.world_grip(player.net_position, player.net_yaw, player.net_pitch).origin
	)
	var direction := ThrowMath.aim_direction(player.net_yaw, player.net_pitch)
	var to := _landing_point(from, direction, distance)
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if holdables:
		holdables.call("spawn_thrown_item", def.id, from, to)
		_play_inventory.rpc_id(peer_id, &"drop")


func _landing_point(from: Vector3, direction: Vector3, distance: float) -> Vector3:
	var flat := ThrowMath.toss_target(from, direction, distance)
	var query := PhysicsRayQueryParameters3D.create(
		flat + Vector3.UP * 10.0, flat + Vector3.DOWN * 10.0
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else flat


## Use the first-person camera only while the owner's body is hidden. F3 and
## remote peers use the same body-relative grip, including the aim pitch.
func _mount_transform(player: Player) -> Transform3D:
	var def := ItemCatalog.find(net_item_id)
	var offset := def.first_person_offset if def != null else HeldItemPose.FIRST_PERSON_OFFSET
	return HeldItemPose.player_mount(player, offset)


func _aim_origin(player: Player) -> Vector3:
	return (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)


func support_grip() -> Node3D:
	return _view.get_node_or_null("SupportGrip") as Node3D if _view != null else null


## The currently mounted item's visual node, or null while unarmed. Exposed so
## purely cosmetic features (e.g. weapon_hotbar's fire recoil) can animate it
## without hand.gd needing to know about them.
func held_view() -> Node3D:
	return _view


func _pose_arms(player: Player) -> void:
	if _view != null:
		_arms.pose_for_player(player, support_grip(), PlayerSkin.TONES[skin_tone_index()])


func _player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer_id):
			return player
	return null


func _rebuild_view() -> void:
	_mounted_item_id = consumption.view_id()
	for child: Node in _mount.get_children():
		_mount.remove_child(child)
		child.queue_free()
	_view = null
	var def := ItemCatalog.find(consumption.view_id())
	if def != null and def.view_scene != null:
		_view = def.view_scene.instantiate() as Node3D
		_mount.add_child(_view)
		HeldItemPose.align_grip(_view)
		var smoke := _view.get_node_or_null("Smoke") as CPUParticles3D
		if smoke != null:
			smoke.emitting = consumption.active()


func _set_flash(active: bool) -> void:
	if _view == null:
		return
	var muzzle := _view.get_node_or_null("Muzzle")
	if muzzle == null:
		return
	var existing := muzzle.get_node_or_null("MuzzleFlash")
	if active and existing == null:
		var light := OmniLight3D.new()
		light.name = "MuzzleFlash"
		light.light_energy = 3.0
		light.omni_range = 2.5
		light.light_color = Color(1.0, 0.85, 0.5)
		muzzle.add_child(light)
	elif not active and existing != null:
		existing.queue_free()


func inventory() -> PlayerInventory:
	return $Inventory as PlayerInventory


## Spawn first; the inventory removes the source item only after this succeeds.
func drop_inventory_item(item_id: String) -> bool:
	if not multiplayer.is_server() or ItemCatalog.find(item_id) == null:
		return false
	var player := _player()
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if player == null or holdables == null:
		return false
	var from := (
		HeldItemPose.world_grip(player.net_position, player.net_yaw, player.net_pitch).origin
	)
	var direction := ThrowMath.aim_direction(player.net_yaw, player.net_pitch)
	holdables.call(
		"spawn_thrown_item", item_id, from, _landing_point(from, direction, DROP_DISTANCE)
	)
	return true


func skin_tone_index() -> int:
	var fallback := (
		skin_index
		if skin_index >= 0 and skin_index < PlayerSkin.TONES.size()
		else PlayerSkin.index_for_id(peer_id)
	)

	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	return models.skin_for(peer_id, fallback) if models != null else fallback
