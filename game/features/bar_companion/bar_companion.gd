class_name BarCompanion
extends Node3D
## Owns every player's charisma, intoxication and lucky-night buff on the server.
## The bartender, Vivienne and the slot machines call into it; clients only read
## the replicated `stats` summary.

## Seconds between refreshes of the replicated summary.
const PUBLISH_S := 0.5

## peer id -> [charisma, intoxication (whole drinks), lucky seconds left]. Replicated.
@export var stats: Dictionary = {}

## peer id -> {"win": float, "intox": float, "luck": float}. Server only.
var store := CharmStore.new()
var _state: Dictionary = {}
var _publish_in := 0.0
var _save_in := 5.0
var _accounts: Dictionary = {}  # cached before Network removes disconnected accounts


func _ready() -> void:
	add_to_group(&"bar_companion")
	store.path = str(Network.args.get("bar-stats-save-path", store.path))
	var entity := $NetworkedEntity as NetworkedEntity
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(forget)


func charisma_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[0]) if row.size() == 3 else 0


func intoxication_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[1]) if row.size() == 3 else 0


func luck_seconds_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[2]) if row.size() == 3 else 0


## Extra slot reel rolls; read on the server by features/slot_machine.
func rerolls_for(peer: int) -> int:
	if multiplayer.is_server():
		return CharmMath.LUCK_REROLLS if float(_row(peer)["luck"]) > 0.0 else 0
	return CharmMath.LUCK_REROLLS if luck_seconds_for(peer) > 0 else 0


func price_for(peer: int) -> int:
	return CharmMath.price_cents(_server_charisma(peer))


## Server-only: a casino win makes the winner briefly more charming.
func note_win(peer: int) -> void:
	if multiplayer.is_server():
		var row := _row(peer)
		row["win"] = minf(float(row["win"]) + CharmMath.WIN_CHARISMA, CharmMath.MAX_WIN_CHARISMA)
		_publish()
		_save()


## Server-only: the bartender served `peer` a drink.
func add_drink(peer: int) -> void:
	if multiplayer.is_server():
		var row := _row(peer)
		row["intox"] = minf(float(row["intox"]) + 1.0, CharmMath.MAX_INTOXICATION)
		_publish()
		_save()


## Server-only: Vivienne was walked to `peer`'s room.
func grant_luck(peer: int) -> void:
	if multiplayer.is_server():
		_row(peer)["luck"] = CharmMath.LUCK_S
		_publish()
		_save()


func forget(peer: int) -> void:
	if multiplayer.is_server():
		_save()
		_accounts.erase(peer)
		_state.erase(peer)
		_publish()


func _server_charisma(peer: int) -> int:
	var row := _row(peer) if multiplayer.is_server() else CharmStore.empty_row()
	return CharmMath.charisma(float(row["win"]), float(row["intox"]))


func _row(peer: int) -> Dictionary:
	var account := (
		int((Network.peer_accounts.get(peer, {}) as Dictionary).get("account_id", 0))
		if Network.mode == Network.Mode.SERVER
		else 0
	)
	if account > 0 and not _accounts.has(peer):
		# A new connection can replace an old one before its disconnect arrives.
		for old: int in _accounts.keys():
			if _accounts[old] == account:
				forget(old)
		_accounts[peer] = account
		_state[peer] = store.restore(account, Time.get_unix_time_from_system())
		_publish()
	if not _state.has(peer):
		_state[peer] = CharmStore.empty_row()
	return _state[peer]


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer: int in Network.peer_accounts:
		if not _accounts.has(peer):
			_row(peer)
	advance(delta)


## Server-only: fades charisma, sobers players up and runs down lucky nights.
func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer: int in _state.keys():
		var row: Dictionary = _state[peer]
		row["win"] = CharmMath.decay(float(row["win"]), delta, CharmMath.WIN_FADE_S)
		row["intox"] = CharmMath.decay(float(row["intox"]), delta, CharmMath.SOBER_S)
		row["luck"] = maxf(float(row["luck"]) - delta, 0.0)
		if is_zero_approx(row["win"]) and is_zero_approx(row["intox"]) and row["luck"] <= 0.0:
			_state.erase(peer)
	_save_in -= delta
	if _save_in <= 0.0:
		_save()
	_publish_in -= delta
	if _publish_in <= 0.0:
		_publish()


func _publish() -> void:
	_publish_in = PUBLISH_S
	var next := {}
	for peer: int in _state:
		var row: Dictionary = _state[peer]
		next[peer] = [
			CharmMath.charisma(float(row["win"]), float(row["intox"])),
			ceili(float(row["intox"])),
			ceili(float(row["luck"]))
		]
	if next != stats:
		stats = next


func _reset(_mode: Network.Mode) -> void:
	_save()
	_state.clear()
	_accounts.clear()
	stats = {}


func _save() -> void:
	if not multiplayer.is_server() or _accounts.is_empty():
		return
	_save_in = 5.0
	var now := Time.get_unix_time_from_system()
	for peer: int in _accounts:
		store.remember(_accounts[peer], _state.get(peer, CharmStore.empty_row()), now)
	store.save()


func _exit_tree() -> void:
	_save()
