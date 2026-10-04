extends GutTest
## Real transport coverage for private hands and drops across join/leave boundaries.

const ZONES := preload("res://features/zone_instances/feature.tscn")
const HOLDABLES := preload("res://features/holdables/feature.tscn")
const GUN_MACHINE := preload("res://features/gun_machine/feature.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")
const CHAT := preload("res://features/chat_box/chat_box.gd")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node3D] = []
var _peers: Array[ENetMultiplayerPeer] = []
var _seen_drops: Dictionary[String, int] = {}
var _seen_projectiles: Dictionary[String, int] = {}


func after_each() -> void:
	for root: Node3D in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()
	_seen_drops.clear()
	_seen_projectiles.clear()
	Controls.pause()


func _branch(title: String, peer: ENetMultiplayerPeer) -> Node3D:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	root.add_child(ZONES.instantiate())
	var holdables := HOLDABLES.instantiate()
	holdables.name = "Holdables"
	root.add_child(holdables)
	_seen_drops[title] = 0
	(holdables.get_node("ThrownSpawner") as MultiplayerSpawner).spawned.connect(
		func(_node: Node) -> void: _seen_drops[title] += 1
	)
	var machine := GUN_MACHINE.instantiate()
	machine.name = "GunMachine"
	root.add_child(machine)
	_seen_projectiles[title] = 0
	(machine.get_node("ProjectileSpawner") as MultiplayerSpawner).spawned.connect(
		func(_node: Node) -> void: _seen_projectiles[title] += 1
	)
	var combat := COMBAT.instantiate()
	combat.name = "Combat"
	root.add_child(combat)
	combat.set_process(false)
	var chat := CHAT.new()
	chat.name = "Chat"
	root.add_child(chat)
	# Keep transport tests disconnected from external relay configuration.
	chat.get_node("DiscordRelay").set("_configured", true)
	return root


func _client(port: int, title: String) -> Node3D:
	var peer := ENetMultiplayerPeer.new()
	assert_eq(peer.create_client("127.0.0.1", port), OK)
	return _branch(title, peer)


func test_private_hands_and_drops_spawn_only_for_members_and_cleanup_on_return() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var owner := _client(transport.host.get_local_port(), "Owner")
	var other := _client(transport.host.get_local_port(), "Other")
	var owner_id := owner.multiplayer.get_unique_id()
	var other_id := other.multiplayer.get_unique_id()
	var hand_path := "Holdables/Hands/%d" % owner_id
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return other.has_node(hand_path), 5.0)
	)
	var zones := server.get_node("ZoneInstances") as ZoneInstances
	var marker := Marker3D.new()
	server.add_child(marker)
	var run := zones.create_excursion(
		[owner_id] as Array[int], marker, SlumInstance.Destination.ALLEYS, 42
	)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not other.has_node(hand_path), 5.0
		)
	)
	assert_true(owner.has_node(hand_path), "Owner retains their own inventory")
	var hand := server.get_node(hand_path) as Hand
	hand.net_item_id = "pistol"
	var holdables := server.get_node("Holdables")
	var origin := run.global_position + Vector3.UP
	holdables.spawn_thrown_item("scrap", origin, origin)
	var drop_path := "Holdables/Thrown/Thrown1"
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return owner.has_node(drop_path), 5.0)
	)
	assert_false(other.has_node(drop_path), "Unrelated hub peer never loads the private drop")
	assert_eq(_seen_drops["Other"], 0, "No temporary initial spawn leaks to outsiders")
	var late := _client(transport.host.get_local_port(), "Late")
	var late_id := late.multiplayer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 3, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_false(late.has_node(hand_path), "Late outsider receives no private hand snapshot")
	assert_false(late.has_node(drop_path), "Late outsider receives no private drop snapshot")
	assert_eq(_seen_drops["Late"], 0)
	assert_true(zones.registry.join(run.instance_id, late_id))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return late.has_node(hand_path) and late.has_node(drop_path),
			5.0
		)
	)
	assert_eq((late.get_node(hand_path) as Hand).net_item_id, "pistol")
	assert_eq((late.get_node(drop_path) as ThrownItem).instance_id, run.instance_id)
	assert_eq(_seen_drops["Late"], 1)
	zones.registry.leave(owner_id)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return not owner.has_node(drop_path) and other.has_node(hand_path),
			5.0
		)
	)
	assert_true(late.has_node(drop_path), "Remaining member keeps the same drop")
	zones.registry.leave(late_id)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return not server.has_node(drop_path) and not late.has_node(drop_path),
			5.0
		)
	)
	assert_eq(zones.registry.instance_of(other_id), -1)


func test_generated_guns_projectiles_and_effects_remain_inside_the_group() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var owner := _client(transport.host.get_local_port(), "Owner")
	var partner := _client(transport.host.get_local_port(), "Partner")
	var outsider := _client(transport.host.get_local_port(), "Other")
	var owner_id := owner.multiplayer.get_unique_id()
	var partner_id := partner.multiplayer.get_unique_id()
	var rig_path := "GunMachine/Rigs/%d" % owner_id
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return outsider.has_node(rig_path), 5.0
		)
	)

	var zones := server.get_node("ZoneInstances") as ZoneInstances
	var marker := Marker3D.new()
	server.add_child(marker)
	var run := zones.create_excursion(
		[owner_id, partner_id] as Array[int], marker, SlumInstance.Destination.ALLEYS, 42
	)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not outsider.has_node(rig_path), 5.0
		)
	)
	var rig := server.get_node(rig_path) as GunRig
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	rig.equip(GunGenerator.generate(rng))
	rig.net_ammo_in_mag -= 1
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (partner.get_node(rig_path) as GunRig).net_ammo_in_mag == rig.net_ammo_in_mag,
			5.0
		)
	)
	var partner_rig := partner.get_node(rig_path) as GunRig
	partner_rig.entity.request_action(&"reload")
	await RealTime.wait(get_tree(), .1)
	assert_eq(
		rig.net_ammo_in_mag,
		int(rig.net_stats["magazine_size"]) - 1,
		"Same-group peers cannot control another player's gun"
	)
	(owner.get_node(rig_path) as GunRig).entity.request_action(&"reload")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return rig.net_ammo_in_mag == int(rig.net_stats["magazine_size"]),
			5.0
		)
	)
	var effects: Array[StringName] = []
	partner_rig.entity.event_received.connect(
		func(event: StringName, _payload: Dictionary) -> void: effects.append(event)
	)
	rig.entity.send_event(
		&"fire",
		{"ammo_type": GunGenerator.AmmoType.LOW_CALIBER, "origin": run.global_position + Vector3.UP}
	)
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return &"fire" in effects, 5.0)
	)
	var machine := server.get_node("GunMachine") as GunMachine
	machine.spawn_projectile(
		{
			"ammo_type": GunGenerator.AmmoType.RAY,
			"position": run.global_position + Vector3(0, 2, 0),
			"velocity": Vector3.ZERO,
			"damage": 20.0,
			"shooter_peer": owner_id
		}
	)
	var projectile_path := "GunMachine/Projectiles/Projectile1"
	var projectile := server.get_node(projectile_path) as Projectile
	projectile.set_physics_process(false)
	assert_eq(projectile.instance_id, run.instance_id)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return partner.has_node(projectile_path), 5.0
		)
	)
	assert_false(outsider.has_node(projectile_path))
	assert_eq(_seen_projectiles["Other"], 0, "No initial projectile snapshot leaks")
	var late := _client(transport.host.get_local_port(), "Late")
	var late_id := late.multiplayer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 4, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_false(late.has_node(rig_path))
	assert_eq(_seen_projectiles["Late"], 0)
	assert_true(zones.registry.join(run.instance_id, late_id))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return late.has_node(projectile_path) and late.has_node(rig_path),
			5.0
		)
	)
	assert_eq((late.get_node(rig_path) as GunRig).net_stats, rig.net_stats)
	zones.registry.leave(owner_id)
	zones.registry.leave(partner_id)
	zones.registry.leave(late_id)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return not server.has_node(projectile_path) and not late.has_node(projectile_path),
			5.0
		)
	)


func test_private_health_and_death_events_reach_only_the_current_group() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var owner := _client(transport.host.get_local_port(), "Owner")
	var partner := _client(transport.host.get_local_port(), "Partner")
	var outsider := _client(transport.host.get_local_port(), "Other")
	var owner_id := owner.multiplayer.get_unique_id()
	var partner_id := partner.multiplayer.get_unique_id()
	var health_path := "Combat/HealthStates/%d" % owner_id
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return outsider.has_node(health_path), 5.0
		)
	)
	var zones := server.get_node("ZoneInstances") as ZoneInstances
	var marker := Marker3D.new()
	server.add_child(marker)
	var id := zones.registry.create([owner_id, partner_id] as Array[int], marker)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not outsider.has_node(health_path), 5.0
		)
	)
	var combat := server.get_node("Combat") as Combat
	combat.apply_enemy_damage(owner_id, 35.0)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					(owner.get_node("Combat") as Combat).health_for(owner_id) == 65.0
					and (partner.get_node("Combat") as Combat).health_for(owner_id) == 65.0
				),
			5.0
		)
	)
	assert_eq((outsider.get_node("Combat") as Combat).health_for(owner_id), 100.0)
	var late := _client(transport.host.get_local_port(), "Late")
	var late_id := late.multiplayer.get_unique_id()
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 4, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_false(late.has_node(health_path))
	assert_true(zones.registry.join(id, late_id))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return (late.get_node("Combat") as Combat).health_for(owner_id) == 65.0,
			5.0
		)
	)
	var deaths: Dictionary[String, int] = {"Owner": 0, "Partner": 0, "Other": 0}
	for root: Node3D in [owner, partner, outsider]:
		var title := String(root.name)
		(root.get_node("Combat") as Combat).player_died.connect(
			func(_victim: int, _attacker: int) -> void: deaths[title] += 1
		)
	combat.apply_enemy_damage(owner_id, 100.0)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return deaths["Owner"] == 1 and deaths["Partner"] == 1, 5.0
		)
	)
	assert_eq(deaths["Other"], 0, "Private deaths do not broadcast to another group")


func _has_chat(root: Node, message: String) -> bool:
	var log := root.get_node("Chat").get("_log") as VBoxContainer
	for line: RichTextLabel in log.get_children():
		if line.text.contains(message):
			return true
	return false


func test_chat_remains_global_between_separate_excursion_groups() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var first := _client(transport.host.get_local_port(), "First")
	var second := _client(transport.host.get_local_port(), "Second")
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var marker := Marker3D.new()
	server.add_child(marker)
	var zones := server.get_node("ZoneInstances") as ZoneInstances
	zones.registry.create([first.multiplayer.get_unique_id()] as Array[int], marker)
	zones.registry.create([second.multiplayer.get_unique_id()] as Array[int], marker)
	(first.get_node("Chat") as CanvasLayer).request_chat_message.rpc_id(1, "Across instances")
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					_has_chat(first, "Across instances") and _has_chat(second, "Across instances")
				),
			5.0
		)
	)
