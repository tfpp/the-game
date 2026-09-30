extends GutTest
## Shared round-flow fixture for roulette table tests: a table, a temporary wallet and
## four players (peers 2-5). Requests go through the real NetworkedInteraction
## evaluation with fake peers.

const TableScene := preload("res://features/roulette/table.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const RESULT := NetworkedEntity.Result

var _table: RouletteTable
var _wallet: PlayerMoney
var _players: Dictionary = {}


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {2: 2000, 3: 2000, 4: 2000, 5: 2000}
	_table = TableScene.instantiate() as RouletteTable
	add_child_autofree(_table)
	_table.set_process(false)
	_players.clear()
	for peer: int in [2, 3, 4, 5]:
		var player := PlayerScene.instantiate() as Player
		player.set_multiplayer_authority(peer)
		player.display_name = "P%d" % peer
		player.position = Vector3((peer - 3) * 0.9, 0.9144, -2.4)
		player.net_position = player.position
		player.net_yaw = PI
		add_child_autofree(player)
		_players[peer] = player
	await get_tree().physics_frame


func _use(peer: int) -> NetworkedEntity.Result:
	return _table.entity._evaluate(peer, &"use", {})


func _act(peer: int, action: StringName, payload: Dictionary = {}) -> NetworkedEntity.Result:
	return _table.entity._evaluate(peer, action, payload)


func _sit(peer: int) -> void:
	assert_eq(_use(peer), RESULT.ACCEPTED, "peer %d sits" % peer)
	var player := _players[peer] as Player
	player.net_position = _table.seat_position(_table.seat_of(peer))
	player.global_position = player.net_position


func _run(seconds: float) -> void:
	var step := 0.25
	var elapsed := 0.0
	while elapsed < seconds:
		_table._process(step)
		elapsed += step


class FlakyWallet:
	extends PlayerMoney
	var ids: Array[String] = []

	func settle_roulette(
		peer: int, _account: int, id: String, wager_cents: int, payout_cents: int
	) -> Dictionary:
		ids.append(id)
		if ids.size() < 3:
			return {"error": "Wallet unavailable — try again"}
		balances[peer] = int(balances[peer]) - wager_cents + payout_cents
		return {"balance": balances[peer]}


class FakeChat:
	extends Node
	var lines: Array[String] = []

	func _ready() -> void:
		add_to_group(&"chat_box")

	func receive_notice(text: String) -> void:
		lines.append(text)


class FixedWheel:
	extends RouletteWheel
	var _number := 0

	func _init(number: int) -> void:
		_number = number

	func next_result() -> int:
		return _number
