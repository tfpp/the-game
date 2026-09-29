extends GutTest

const DEALER := preload("res://features/casino_patrons/stationary_dealer.tscn")
const SALON := preload("res://features/casino_hub/salon.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const ROUND := preload("res://features/gun_machine/projectile.tscn")

var _npc: StationaryPatron


func before_each() -> void:
	_npc = DEALER.instantiate() as StationaryPatron
	add_child_autofree(_npc)
	_npc.set_physics_process(false)


func test_death_disables_body_and_repeated_hits_do_not_delay_respawn() -> void:
	watch_signals(_npc._entity)
	_npc.take_hit(1)
	_npc._physics_process(3.0)
	_npc.take_hit(2)
	await wait_physics_frames(2)
	assert_false(_npc.net_alive)
	assert_false(_npc._body.visible)
	assert_true(_npc._collider.disabled)
	assert_signal_emit_count(_npc._entity, "event_received", 1)
	_npc._physics_process(3.0)
	await wait_physics_frames(2)
	assert_true(_npc.net_alive)
	assert_true(_npc._body.visible)
	assert_false(_npc._collider.disabled)


func test_late_dead_snapshot_hides_model_without_replaying_explosion() -> void:
	var late := DEALER.instantiate() as StationaryPatron
	late.net_alive = false
	add_child_autofree(late)
	late.set_physics_process(false)
	await wait_physics_frames(2)
	assert_false(late._body.visible)
	assert_true(late._collider.disabled)
	assert_eq(late.find_children("*", "MeshExplosion", false).size(), 0)
	var sync := late._entity.get_node("Sync") as MultiplayerSynchronizer
	assert_same(sync.get_node(sync.root_path), late)
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:net_alive")))
	late.net_alive = true
	await wait_physics_frames(2)
	assert_true(late._body.visible)
	assert_false(late._collider.disabled)


func test_unregistered_death_requests_cannot_kill_and_session_reset_revives() -> void:
	_npc._entity.request_action(&"death", {"peer": 1})
	assert_true(_npc.net_alive)
	_npc._entity.set_multiplayer_authority(2)
	_npc.take_hit(1)
	assert_true(_npc.net_alive, "non-authority cannot commit a death")
	_npc._entity.set_multiplayer_authority(1)
	_npc.take_hit(1)
	_npc._entity._on_session_changed(Network.Mode.OFFLINE)
	assert_true(_npc.net_alive)


func test_real_hitscan_kills_the_imported_model() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_npc.position = hand._aim_origin(player) + Vector3(0, -1.3, -3)
	await wait_physics_frames(2)
	hand.net_item_id = "pistol"
	hand.request_primary_action()
	assert_false(_npc.net_alive)


func test_every_projectile_ammo_hits_the_real_body() -> void:
	_npc.position = Vector3(0, 0, -3)
	for ammo: int in GunGenerator.AmmoType.values():
		_npc.net_alive = true
		await wait_physics_frames(2)
		var round_node := ROUND.instantiate() as Projectile
		round_node.ammo_type = ammo as GunGenerator.AmmoType
		round_node.shooter_peer = 1
		round_node.net_position = Vector3(0, 1.3, 0)
		round_node.velocity = Vector3(0, 0, -30)
		add_child_autofree(round_node)
		round_node.set_physics_process(false)
		round_node._physics_process(0.12)
		assert_false(_npc.net_alive, "ammo %d kills a stationary NPC" % ammo)
		await wait_physics_frames(1)
	await wait_seconds(0.2)  # Let projectile impact flashes clean themselves up.


func test_all_seventeen_salon_characters_keep_their_poses_and_gain_hitboxes() -> void:
	var salon := SALON.instantiate() as Node3D
	add_child_autofree(salon)
	var count := 0
	for child: Node in salon.get_children():
		if child is StationaryPatron:
			var patron := child as StationaryPatron
			count += 1
			assert_true(patron.is_in_group(&"killable"))
			assert_eq(patron.collision_layer, 2)
			var size := (patron._collider.shape as BoxShape3D).size
			assert_gt(size.y, 0.5)
			assert_lt(size.y, 2.5)
	assert_eq(count, 17)
	assert_eq(salon.get_node("GuestGallery").position, Vector3(2.5, 3.2, -8.6))
	assert_eq(salon.get_node("Patron0_1").position, Vector3(-4, -1.5, -4.65))
