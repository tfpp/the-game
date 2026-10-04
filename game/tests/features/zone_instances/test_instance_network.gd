extends GutTest

const ZONES := preload("res://features/zone_instances/feature.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()


func _branch(title: String, peer: ENetMultiplayerPeer) -> ZoneInstances:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	var zones := ZONES.instantiate() as ZoneInstances
	root.add_child(zones)
	return zones


func test_two_groups_receive_only_their_own_spawned_maps_and_late_member_gets_map() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var first_peer := ENetMultiplayerPeer.new()
	assert_eq(first_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var server := _branch("Server", server_peer)
	var first := _branch("First", first_peer)
	var second_peer := ENetMultiplayerPeer.new()
	assert_eq(second_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var second := _branch("Second", second_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var marker := Marker3D.new()
	server.add_child(marker)
	var a := server.create_excursion(
		[first_peer.get_unique_id()] as Array[int], marker, SlumInstance.Destination.ALLEYS, 100
	)
	var b := server.create_excursion(
		[second_peer.get_unique_id()] as Array[int], marker, SlumInstance.Destination.ALLEYS, 200
	)
	var a_path := "Instances/" + String(a.name)
	var b_path := "Instances/" + String(b.name)
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return first.has_node(a_path) and second.has_node(b_path),
			5.0
		)
	)
	assert_false(first.has_node(b_path), "First group never loads second group's scene")
	assert_false(second.has_node(a_path), "Second group never loads first group's scene")
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("Late", late_peer)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 3, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_eq(
		late.get_node("Instances").get_child_count(), 0, "Unassigned late peer receives no slum"
	)
	assert_true(server.registry.join(a.instance_id, late_peer.get_unique_id()))
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return late.has_node(a_path), 5.0)
	)
	assert_false(late.has_node(b_path))
	assert_eq((late.get_node(a_path) as SlumInstance).layout_seed, 100)
	server.registry.leave(first_peer.get_unique_id())
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return not first.has_node(a_path), 5.0
		)
	)
	assert_true(late.has_node(a_path), "Remaining member keeps the map")
	server.registry.leave(late_peer.get_unique_id())
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return not late.has_node(a_path), 5.0)
	)
	assert_true(second.has_node(b_path))


func test_garage_enemy_and_loot_current_state_survives_late_entry_and_reentry() -> void:
	var transport := ENetMultiplayerPeer.new()
	assert_eq(transport.create_server(0), OK)
	var server := _branch("Server", transport)
	var member_transport := ENetMultiplayerPeer.new()
	assert_eq(member_transport.create_client("127.0.0.1", transport.host.get_local_port()), OK)
	var member := _branch("Member", member_transport)
	var outsider_transport := ENetMultiplayerPeer.new()
	assert_eq(outsider_transport.create_client("127.0.0.1", transport.host.get_local_port()), OK)
	var outsider := _branch("Outsider", outsider_transport)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5.0
		)
	)
	var marker := Marker3D.new()
	server.add_child(marker)
	var instance := server.create_excursion(
		[member_transport.get_unique_id()] as Array[int],
		marker,
		SlumInstance.Destination.GARAGE,
		73021
	)
	var path := "Instances/" + String(instance.name)
	var enemy_path := path + "/Map/CrownGarage/Enemies/Enemy0"
	var loot_path := path + "/Map/CrownGarage/Loot/B1Crate0"
	var world := instance.get_node("Map/CrownGarage")
	for enemy: GarageEnemy in world.get_node("Enemies").get_children():
		enemy.set_physics_process(false)
	var enemy := server.get_node(enemy_path) as GarageEnemy
	var loot := server.get_node(loot_path) as LootContainer
	enemy.net_alive = false
	loot.net_searched = true
	loot.net_contents = PackedStringArray(["watch"])
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					member.has_node(enemy_path)
					and not (member.get_node(enemy_path) as GarageEnemy).net_alive
					and (
						(member.get_node(loot_path) as LootContainer).net_contents
						== loot.net_contents
					)
				),
			5.0
		)
	)
	assert_false(outsider.has_node(path))
	var late_transport := ENetMultiplayerPeer.new()
	assert_eq(late_transport.create_client("127.0.0.1", transport.host.get_local_port()), OK)
	var late := _branch("Late", late_transport)
	assert_true(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 3, 5.0
		)
	)
	await RealTime.wait(get_tree(), .1)
	assert_false(late.has_node(path))
	assert_true(server.registry.join(instance.instance_id, late_transport.get_unique_id()))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					late.has_node(enemy_path)
					and not (late.get_node(enemy_path) as GarageEnemy).net_alive
					and (
						(late.get_node(loot_path) as LootContainer).net_contents
						== loot.net_contents
					)
				),
			5.0
		)
	)
	server.registry.leave(late_transport.get_unique_id())
	assert_true(
		await RealTime.wait_until(get_tree(), func() -> bool: return not late.has_node(path), 5.0)
	)
	enemy.net_alive = true
	loot.net_contents = PackedStringArray(["jewelry"])
	assert_true(server.registry.join(instance.instance_id, late_transport.get_unique_id()))
	assert_true(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					late.has_node(enemy_path)
					and (late.get_node(enemy_path) as GarageEnemy).net_alive
					and (
						(late.get_node(loot_path) as LootContainer).net_contents
						== loot.net_contents
					)
				),
			5.0
		)
	)
	assert_false(outsider.has_node(path), "Encounter updates never cause outsider map loading")
