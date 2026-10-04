extends Node3D
## Private voluntary filings; the shared wallet remains the sole money authority.

const MAX_TAX_CENTS := 100_00  # Existing signed charge API limit, not tax advice.
const MAX_WINNINGS_CENTS := 1_000_000_000_00
const WARNING := "If you aren't truthful, you will go to jail."

var _filings: Dictionary[int, Dictionary] = {}
var _generation := 0

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open, 0.2)
	entity.register_action(&"file", _may_file, _file)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_forget)


func can_use(player: Player) -> bool:
	return entity.in_range(player)


func interaction_text() -> String:
	return "IRS desk — declare gambling winnings"


func use() -> void:
	entity.request_use()


## Parse dollars exactly, without floats, signs, exponents or overflow.
static func parse_amount(value: String, maximum: int) -> int:
	var parts := value.strip_edges().split(".")
	if parts.size() > 2 or parts[0].is_empty() or parts[0].length() > 11:
		return -1
	for part: String in parts:
		if part.is_empty():
			return -1
		for character: String in part:
			if character < "0" or character > "9":
				return -1
	if parts.size() == 2 and parts[1].length() > 2:
		return -1
	var cents := int(parts[0]) * 100
	if parts.size() == 2:
		cents += int(parts[1]) * (10 if parts[1].length() == 1 else 1)
	return cents if cents <= maximum else -1


func _open(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var row: Dictionary = _filings.get(peer, {})
	if row.is_empty() or row["player"].get_ref() != player:
		row = {"token": _new_id(), "player": weakref(player), "busy": false}
		_filings[peer] = row
	var payload := {"token": row["token"], "locked": row.has("tax"), "busy": row["busy"]}
	if row.has("tax"):
		payload["tax"] = row["tax"]
		payload["winnings"] = row["winnings"]
	entity.send_event(&"form", payload, peer)
	return true


func _may_file(peer: int, payload: Dictionary) -> bool:
	var player := entity.player_for_peer(peer)
	if not can_use(player) or not _filings.has(peer):
		return false
	var row := _filings[peer]
	if row["busy"] or row["player"].get_ref() != player:
		return false
	if (
		payload.size() != 3
		or payload.get("token") != row["token"]
		or not payload.get("tax") is int
		or not payload.get("winnings") is int
	):
		return false
	var tax: int = payload["tax"]
	var winnings: int = payload["winnings"]
	if tax < 0 or tax > MAX_TAX_CENTS or winnings < 0 or winnings > MAX_WINNINGS_CENTS:
		return false
	if row.has("tax"):
		var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
		return (
			wallet != null
			and wallet.account_for(peer) == row["account"]
			and row["tax"] == tax
			and row["winnings"] == winnings
		)
	return true


func _file(peer: int, payload: Dictionary) -> bool:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		return false
	var row := _filings[peer]
	if not row.has("tax"):
		row["tax"] = payload["tax"]
		row["winnings"] = payload["winnings"]
		row["account"] = wallet.account_for(peer)
	row["busy"] = true
	_settle(wallet, peer, row)
	return true


func _settle(wallet: PlayerMoney, peer: int, row: Dictionary) -> void:
	var generation := _generation
	var result := {"balance": 0}
	if row["tax"] > 0:
		result = await wallet.adjust_account(
			peer, row["account"], row["token"], -int(row["tax"]), "Voluntary gambling tax"
		)
	if not is_inside_tree() or generation != _generation:
		return
	row["busy"] = false
	var same_player: bool = (
		_filings.has(peer)
		and _filings[peer]["token"] == row["token"]
		and is_instance_valid(row["player"].get_ref())
		and entity.player_for_peer(peer) == row["player"].get_ref()
		and wallet.account_for(peer) == row["account"]
	)
	if not same_player:
		return
	var success := result.has("balance")
	var terminal := success or bool(result.get("rejected", false))
	if terminal:
		_filings.erase(peer)
	var message := (
		"Declaration received. Tax paid: %s.\n%s" % [PlayerMoney.format_money(row["tax"]), WARNING]
	)
	if not success:
		message = (
			"Payment refused. Close and Use to file again."
			if terminal
			else "Payment unconfirmed. Retry the same filing; do not submit a new one."
		)
	entity.send_event(
		&"receipt", {"text": message, "retry": not terminal, "token": row["token"]}, peer
	)


func _forget(peer: int) -> void:
	_filings.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_filings.clear()


func _new_id() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()
