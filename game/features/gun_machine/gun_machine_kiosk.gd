class_name GunMachineKiosk
extends StaticBody3D
## The machine itself: pays a fixed price from a player's wallet for a freshly
## rolled gun (see gun_machine.gd's `purchase`), replacing whatever they currently
## carry. Balance and price are both shown up front, the same way
## features/slot_machine shows its cost and your wallet, so a purchase that can't be
## afforded just silently doesn't happen — there's nothing to explain.

const USE_RANGE := 3.0

var _pending := false


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	if _pending:
		return "Gun machine — dispensing…"
	var text := "Buy a random gun — %s" % PlayerMoney.format_money(_price_cents())
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet != null and wallet.balances.has(multiplayer.get_unique_id()):
		text += (
			" (you have %s)"
			% PlayerMoney.format_money(int(wallet.balances[multiplayer.get_unique_id()]))
		)
	return text


func can_use(player: Player) -> bool:
	return not _pending and global_position.distance_to(player.net_position) <= USE_RANGE


func use() -> void:
	request_purchase.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_purchase() -> void:
	if not multiplayer.is_server() or _pending:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	_pending = true
	var machine := get_tree().get_first_node_in_group(&"gun_machine_root")
	if machine != null:
		var error: String = await machine.call("purchase", peer_id)
		var rig := GunRig.for_peer(get_tree(), peer_id)
		if error == "" and rig != null:
			play_assembly.rpc(rig.net_stats)
	_pending = false


## Server -> everyone: animate the machine building the gun that was just sold.
## Cosmetic only; the gun itself is already equipped server-side.
@rpc("authority", "call_local", "reliable")
func play_assembly(stats: Dictionary) -> void:
	if stats.is_empty():
		return
	var cabinet := get_node_or_null(^"Cabinet") as GunMachineCabinet
	if cabinet != null:
		cabinet.assemble(stats)


func _price_cents() -> int:
	var machine := get_tree().get_first_node_in_group(&"gun_machine_root")
	return int(machine.call("price_cents")) if machine != null else 0


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
