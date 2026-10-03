class_name GarageJobTerminal
extends Node3D
## Optional survey contracts. The terminal owns session progress, never a second wallet.

const SURVEY_SECONDS := 3.0
const XP_REWARD := 25

@export var records: Dictionary = {}
@export var van_path: NodePath
@export var panel_path: NodePath
var _survey_time: Dictionary[int, float] = {}
var _paying: Dictionary[int, bool] = {}
var _operations: Dictionary[int, String] = {}
var _generation := 0
var _tick := 0.0
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var van: OperationsVan = get_node(van_path)
@onready var panel: GarageJobPanel = get_node(panel_path)


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open)
	entity.register_action(&"accept", _may_accept, _accept)
	entity.register_action(&"claim", _may_claim, _claim)
	panel.terminal = self
	entity.request_finished.connect(panel.request_result)
	entity.event_received.connect(_event)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_disconnect)


func interaction_text() -> String:
	return "CRT computer · open Crown OS desktop"


func can_use(player: Player) -> bool:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return (
		entity.in_range(player)
		and (combat == null or not combat.is_respawning(player.get_multiplayer_authority()))
	)


func use() -> void:
	entity.request_use()


func record(peer: int) -> Dictionary:
	return records.get(peer, {"job": -1, "ready": false, "done": [], "xp": 0})


func _open(player: Player) -> bool:
	entity.send_event(&"open", {}, player.get_multiplayer_authority())
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"open":
		panel.open(self)
	elif event == &"error":
		panel.message = str(payload.get("message", "Reward unavailable. Try again."))


func _may_accept(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.get("job") is int:
		return false
	var job := int(payload["job"])
	var data := record(peer)
	return (
		can_use(entity.player_for_peer(peer))
		and van.arrival(job) != null
		and int(data["job"]) == -1
		and job not in data["done"]
	)


func _accept(peer: int, payload: Dictionary) -> bool:
	var data := record(peer).duplicate(true)
	data["job"] = int(payload["job"])
	data["ready"] = false
	_store(peer, data)
	_survey_time.erase(peer)
	return true


func _may_claim(peer: int, payload: Dictionary) -> bool:
	return (
		payload.is_empty()
		and can_use(entity.player_for_peer(peer))
		and bool(record(peer)["ready"])
		and not _paying.has(peer)
		and get_tree().get_first_node_in_group(&"player_money") != null
	)


func _claim(peer: int, _payload: Dictionary) -> bool:
	_paying[peer] = true
	if not _operations.has(peer):
		_operations[peer] = Crypto.new().generate_random_bytes(32).hex_encode()
	# NetworkedEntity callbacks must not yield. Lock first, then settle asynchronously.
	_settle.call_deferred(peer, _generation)
	return true


func _settle(peer: int, generation: int) -> void:
	if generation != _generation or not _paying.has(peer):
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var result := await wallet.credit_coin(peer, _operations[peer], "Completed garage survey job")
	if generation != _generation or not records.has(peer):
		return
	_paying.erase(peer)
	if not result.has("balance"):
		entity.send_event(&"error", {"message": "Wallet unavailable. Return here and retry."}, peer)
		return
	var data := record(peer).duplicate(true)
	(data["done"] as Array).append(int(data["job"]))
	data["xp"] = int(data["xp"]) + XP_REWARD
	data["job"] = -1
	data["ready"] = false
	_store(peer, data)
	_operations.erase(peer)


func _physics_process(delta: float) -> void:
	if (
		multiplayer.multiplayer_peer == null
		or (
			multiplayer.multiplayer_peer.get_connection_status()
			!= MultiplayerPeer.CONNECTION_CONNECTED
		)
		or not multiplayer.is_server()
	):
		return
	_tick += delta
	if _tick < .25:
		return
	var elapsed := _tick
	_tick = 0
	for peer: int in records.keys():
		var data := record(peer)
		var job := int(data["job"])
		if job < 0 or bool(data["ready"]):
			continue
		var player := entity.player_for_peer(peer)
		var target := van.arrival(job)
		var combat := get_tree().get_first_node_in_group(&"combat") as Combat
		if (
			player == null
			or target == null
			or (combat != null and combat.is_respawning(peer))
			or player.net_position.distance_to(target.global_position) > 5.0
		):
			_survey_time.erase(peer)
			continue
		_survey_time[peer] = _survey_time.get(peer, 0.0) + elapsed
		if _survey_time[peer] >= SURVEY_SECONDS:
			data = data.duplicate(true)
			data["ready"] = true
			_store(peer, data)
			_survey_time.erase(peer)


func _store(peer: int, data: Dictionary) -> void:
	records = records.duplicate(true)
	records[peer] = data


func _disconnect(peer: int) -> void:
	if not multiplayer.is_server():
		return
	records = records.duplicate(true)
	records.erase(peer)
	_survey_time.erase(peer)
	_paying.erase(peer)
	_operations.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	records = {}
	_survey_time.clear()
	_paying.clear()
	_operations.clear()
	panel.close(false)
	panel.desktop.reset_session()
