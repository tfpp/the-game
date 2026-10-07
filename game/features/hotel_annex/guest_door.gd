class_name HotelGuestDoor
extends SwingDoor
## Hotel tenure is separate from Lily Apartments' free unit allocation.

const RENT_CENTS := 1000
const BUY_CENTS := 10000
const RENT_SECONDS := 1800.0
const GuestPanel := preload("res://features/hotel_annex/guest_panel.gd")

@export var occupant := ""
@export var tenure := ""
@export var reservation := ""
@export var locked := false
@export var guests: Array[int] = []
@export var remaining := 0.0
@export var interior_side := 1.0

var _owner := ""
var _pending: Dictionary = {}
var _paying := false
var _generation := 0
var _panel: CanvasLayer
var _nameplates: Array[Label3D] = []


func _ready() -> void:
	super._ready()
	_entity.register_action(&"manage", _validate_manage, _manage, 0.45)
	multiplayer.peer_disconnected.connect(_disconnected)
	for side: float in [-1.0, 1.0]:
		var plate := Label3D.new()
		plate.position = Vector3((width - 0.08) / 2, height * 0.7, side * 0.13)
		plate.rotation.y = PI if side < 0 else 0.0
		plate.font_size = 32
		plate.pixel_size = 0.003
		plate.no_depth_test = false
		plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plate.width = 500
		_pivot.add_child(plate)
		_nameplates.append(plate)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if multiplayer.is_server() and tenure == "Rental":
		remaining = maxf(0, remaining - delta)
		if remaining == 0:
			_vacate()
	for plate: Label3D in _nameplates:
		plate.text = door_label + "\n" + (occupant if not occupant.is_empty() else "Available")


func can_use(player: Player) -> bool:
	if not super.can_use(player):
		return false
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return combat == null or not combat.is_respawning(player.get_multiplayer_authority())


func interaction_text() -> String:
	return "Manage " + door_label


## Use opens a private panel; physical movement still uses SwingDoor's callback.
func _toggle(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	_entity.send_event(
		&"panel", {"owner": not _owner.is_empty() and _owner == _identity(peer)}, peer
	)
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if event != &"panel":
		super._event(event, payload)
		return
	if not is_instance_valid(_panel):
		_panel = GuestPanel.new()
		add_child(_panel)
	_panel.call("open", self, bool(payload.get("owner", false)))


func request_manage(operation: String, guest: int = 0) -> void:
	var payload := {"operation": operation}
	if operation == "guest":
		payload["guest"] = guest
	_entity.request_action(&"manage", payload)


# gdlint: disable=max-returns
func _validate_manage(peer: int, payload: Dictionary) -> bool:
	var player := _entity.player_for_peer(peer)
	if not can_use(player) or not payload.get("operation") is String:
		return false
	var operation: String = payload["operation"]
	if payload.size() != (2 if operation == "guest" else 1):
		return false
	if operation in ["rent", "buy"]:
		return (
			_owner.is_empty()
			and not _paying
			and (
				_pending.is_empty()
				or (_pending["owner"] == _identity(peer) and _pending["operation"] == operation)
			)
		)
	if operation == "toggle":
		# Never trap somebody inside after a revocation, rental expiry or reconnect.
		return not locked or _owner == _identity(peer) or peer in guests or _inside(player)
	if _owner.is_empty() or _owner != _identity(peer) or _paying:
		return false
	if operation == "guest":
		return (
			payload.get("guest") is int
			and int(payload["guest"]) != peer
			and _entity.player_for_peer(int(payload["guest"])) != null
		)
	return operation in ["lock", "leave"]


func _manage(peer: int, payload: Dictionary) -> bool:
	match payload["operation"]:
		"rent", "buy":
			if _pending.is_empty():
				var player := _entity.player_for_peer(peer)
				_pending = {
					"owner": _identity(peer),
					"operation": payload["operation"],
					"name": player.display_name if not player.display_name.is_empty() else "Guest",
					"id": Crypto.new().generate_random_bytes(32).hex_encode()
				}
			reservation = _pending["name"]
			_paying = true
			_pay.call_deferred(peer, str(payload["operation"]), _generation)
		"toggle":
			return super._toggle(_entity.player_for_peer(peer))
		"lock":
			# Locking never slams the moving leaf through a player.
			locked = not locked
		"leave":
			_vacate()
		"guest":
			var next := guests.duplicate()
			var guest: int = payload["guest"]
			if guest in next:
				next.erase(guest)
			else:
				next.append(guest)
			guests = next
	return true


func _identity(peer: int) -> String:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	var id := int(account.get("account_id", 0))
	return "account:%d" % id if id > 0 else "guest:%d" % peer


func _inside(player: Player) -> bool:
	# West leaves face the gallery; east leaves face their rooms.
	return to_local(player.net_position).z * interior_side > 0.2


func _pay(peer: int, operation: String, generation: int) -> void:
	if generation != _generation or _pending.is_empty():
		return
	if _entity.player_for_peer(peer) == null or _identity(peer) != _pending["owner"]:
		_paying = false
		if str(_pending["owner"]).begins_with("guest:"):
			_pending.clear()
			reservation = ""
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		_paying = false
		return
	var result: Dictionary = await wallet.charge(
		peer, str(_pending["id"]), RENT_CENTS if operation == "rent" else BUY_CENTS
	)
	if generation != _generation or not is_inside_tree():
		return
	_paying = false
	if result.has("balance"):
		_owner = _pending["owner"]
		occupant = _pending["name"]
		tenure = "Rental" if operation == "rent" else "Purchased (session)"
		remaining = RENT_SECONDS if operation == "rent" else 0.0
		locked = true
		_pending.clear()
		reservation = ""
		# A disconnected guest has no stable identity to reclaim.
		if _owner.begins_with("guest:") and _entity.player_for_peer(peer) == null:
			_vacate()
	else:
		# An uncertain transport response retains the exact receipt and vacancy lock.
		if (
			result.has("rejected")
			or (
				str(result.get("error", ""))
				in ["You can't afford that", "Wallet loading — try again"]
			)
		):
			_pending.clear()
			reservation = ""
	_entity.send_event(
		&"notice",
		{"text": str(result.get("error", "Room acquired")), "owner": _owner == _identity(peer)},
		peer
	)


func _vacate() -> void:
	_owner = ""
	occupant = ""
	tenure = ""
	locked = false
	guests = []
	remaining = 0.0
	# Keep the physical leaf where it is; no collision is teleported onto occupants.


func _disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var next := guests.duplicate()
	next.erase(peer)
	guests = next
	if _owner == "guest:%d" % peer:
		_vacate()
	if not _paying and _pending.get("owner", "") == "guest:%d" % peer:
		_pending.clear()
		reservation = ""


func _reset(mode: Network.Mode) -> void:
	super._reset(mode)
	_generation += 1
	_pending.clear()
	reservation = ""
	_paying = false
	_vacate()
	if is_instance_valid(_panel):
		_panel.call("close")
