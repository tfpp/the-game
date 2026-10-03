class_name BusboyShift
extends Node3D
## A single shared, server-owned shift. Cargo is a temporary task, not inventory loot.

const DURATION := 120.0
const DIRTY_LIMIT := 8
const ORDER_DEADLINE := 35.0
const GLASS := preload("res://features/hotel_props/props/drinking_glass.tscn")
const POINT := preload("res://features/bar_companion/busboy_point.gd")
const TABLE_CARD := preload("res://features/bar_companion/table_card.tscn")
const COCKTAIL_TABLE := preload(
	"res://features/casino_props/props/bundle/walnut-pedestal-cocktail-table.tscn"
)
# Tops: card table -0.78 + 0.94/2; cocktail table 0 + 1.045.
const TABLES: Array[Vector3] = [
	Vector3(-5.5, -0.31, -5.9),
	Vector3(-5.5, -0.31, -0.9),
	Vector3(-5.5, -0.31, 3.7),
	Vector3(19.6, 1.045, 8),
	Vector3(-20.5, 1.045, 15.5),
	Vector3(-20, 1.045, -15),
	Vector3(20, 1.045, -8),
	Vector3(20, 1.045, 14)
]
const PATRONS: Array[Vector3] = [
	Vector3(-3.838299, -0.25, -5.103984),
	Vector3(-3.838299, -0.25, -0.103984),
	Vector3(-3.838299, -0.25, 4.496016)
]

@export var snapshot: Dictionary = {}
var worker := 0
var elapsed := 0.0
var dirty: Array[int] = []
var orders: Dictionary = {}
var cargo := -1  # -1 none, -2 empty glass, >=0 ordered drink target
var cleared := 0
var served := 0
var phase := "idle"
var _glass_in := 12.0
var _order_in := 30.0
var _publish_in := 0.0
var _player: Player
var _prize_id := ""
var _pending := false
var _generation := 0
var _points: Array[Node3D] = []
var _carry: Node3D
var _last_snapshot: Dictionary = {}

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_disconnect)
	_connect_combat.call_deferred()
	_add_point("Bar", 0, Vector3(-9.9, -0.27, -9.6))
	for table: int in TABLES.size():
		if table >= 5:
			var furniture := COCKTAIL_TABLE.instantiate() as Node3D
			furniture.name = "Table%d" % (table + 1)
			furniture.position = TABLES[table] - Vector3.UP * 1.045
			add_child(furniture)
		var card := TABLE_CARD.instantiate() as Node3D
		card.name = "TableCard%d" % (table + 1)
		card.set("number", table + 1)
		card.position = (
			TABLES[table] + (Vector3(-1.4, 0, -0.13) if table < 3 else Vector3(0, 0, 0.20))
		)
		card.rotation.y = -PI * 0.5 if table < 3 else 0.0
		add_child(card)
		for slot: int in 3:
			_add_point(
				"Glass%d" % (table * 3 + slot),
				1,
				(
					TABLES[table]
					+ Vector3(
						(slot - 1) * 0.13 - (1.4 if table < 3 else 0.0),
						0,
						-0.16 if table >= 3 else 0.12
					)
				),
				table * 3 + slot
			)
	for index: int in PATRONS.size():
		_add_point("Order%d" % index, 2, PATRONS[index], index)
	_carry = Node3D.new()
	_carry.name = "Cargo"
	var empty := glass_view()
	empty.name = "Empty"
	_carry.add_child(empty)
	var drink := ItemCatalog.create_view("beer")
	drink.name = "Drink"
	_carry.add_child(drink)
	add_child(_carry)
	_carry.visible = false
	process_priority = 21


func _connect_combat() -> void:
	# Features load alphabetically: combat may not exist during the bar's _ready.
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null and not combat.player_died.is_connected(_death):
		combat.player_died.connect(_death)


func _add_point(label: String, kind: int, spot: Vector3, index: int = -1) -> void:
	var point := Node3D.new()
	point.set_script(POINT)
	point.name = label
	point.set("kind", kind)
	point.set("index", index)
	point.position = spot
	add_child(point)
	_points.append(point)


static func glass_view() -> Node3D:
	var source := GLASS.instantiate()
	var model := source.get_node("Model").duplicate() as Node3D
	source.free()
	return model


static func glass_interval(seconds: float) -> float:
	return lerpf(12.0, 4.0, clampf(seconds / DURATION, 0, 1))


static func order_interval(seconds: float) -> float:
	return lerpf(24.0, 10.0, clampf(seconds / DURATION, 0, 1))


# gdlint: disable=max-returns
func eligible(player: Player, kind: int, index: int) -> bool:
	if not is_instance_valid(player):
		return false
	var peer := player.get_multiplayer_authority()
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null and combat.is_respawning(peer):
		return false
	var state := snapshot
	var owner := int(state.get("worker", 0))
	var mode := str(state.get("phase", "idle"))
	if kind == 0 and mode in ["idle", "failed", "paid"]:
		return true
	if peer != owner:
		return false
	if kind == 0:
		if mode == "prize":
			return not _pending
		return (
			mode == "active"
			and (
				int(state.get("cargo", -1)) == -2
				or (
					int(state.get("cargo", -1)) == -1
					and not (state.get("orders", {}) as Dictionary).is_empty()
				)
			)
		)
	if mode != "active":
		return false
	var held := int(state.get("cargo", -1))
	if kind == 1:
		return held == -1 and index in (state.get("dirty", []) as Array)
	return held == index and (state.get("orders", {}) as Dictionary).has(index)


func act(player: Player, kind: int, index: int) -> bool:
	if not entity.is_authority() or not eligible(player, kind, index):
		return false
	if kind == 0:
		if phase in ["idle", "failed", "paid"]:
			_start(player)
		elif phase == "prize":
			_claim()
		elif cargo == -2:
			cargo = -1
			cleared += 1
		elif cargo == -1 and not orders.is_empty():
			cargo = int(orders.keys()[0])
		else:
			return false
	elif kind == 1:
		dirty.erase(index)
		cargo = -2
	else:
		orders.erase(index)
		cargo = -1
		served += 1
	_publish()
	return true


func _start(player: Player) -> void:
	_generation += 1
	worker = player.get_multiplayer_authority()
	_player = player
	elapsed = 0.0
	dirty.clear()
	orders.clear()
	cargo = -1
	cleared = 0
	served = 0
	_glass_in = 12.0
	_order_in = 30.0
	phase = "active"
	_prize_id = Crypto.new().generate_random_bytes(32).hex_encode()
	# Start with visible, nearby work instead of twelve seconds of silent no-op Use.
	dirty.append(0)


func _process(delta: float) -> void:
	if entity.is_authority():
		advance(delta)
	if Network.mode != Network.Mode.SERVER:
		_present()


## Server simulation, sliced at one-second boundaries even after a long frame.
func advance(delta: float) -> void:
	if not entity.is_authority() or phase != "active":
		return
	if not is_instance_valid(_player) or _player != _bar_player():
		_finish("failed")
		return
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null and combat.is_respawning(worker):
		_finish("failed")
		return
	var remaining := maxf(delta, 0)
	while remaining > 0 and phase == "active":
		var step := minf(remaining, 1.0)
		remaining -= step
		elapsed += step
		for index: int in orders.keys():
			orders[index] = float(orders[index]) - step
			if float(orders[index]) <= 0:
				_finish("failed")
				break
		if phase != "active":
			break
		if elapsed >= DURATION:
			_finish("prize" if cleared > 0 and orders.is_empty() else "failed")
			break
		_glass_in -= step
		_order_in -= step
		if _glass_in <= 0:
			spawn_empty()
			_glass_in += glass_interval(elapsed)
		if _order_in <= 0:
			_spawn_order()
			_order_in += order_interval(elapsed)
	_publish_in -= delta
	if _publish_in <= 0:
		_publish()


func spawn_empty() -> void:
	if not entity.is_authority() or phase != "active":
		return
	if dirty.size() >= DIRTY_LIMIT:
		_finish("failed")
		return
	var free: Array[int] = []
	for index: int in TABLES.size() * 3:
		if index not in dirty:
			free.append(index)
	dirty.append(free.pick_random())
	_publish()


func _spawn_order() -> void:
	var free: Array[int] = []
	for index: int in PATRONS.size():
		if not orders.has(index) and _patron_alive(index):
			free.append(index)
	if not free.is_empty():
		orders[free.pick_random()] = ORDER_DEADLINE
	_publish()


func _patron_alive(index: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"killable"):
		if node is StationaryPatron and node.name == "Patron%d_0" % index:
			return (node as StationaryPatron).net_alive
	return false


func _finish(result: String) -> void:
	phase = result
	dirty.clear()
	orders.clear()
	cargo = -1
	_publish()


func _claim() -> void:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null or _pending:
		return
	_pending = true
	var generation := _generation
	var result: Dictionary = await wallet.credit_coin(worker, _prize_id, "Busboy shift complete")
	if not is_inside_tree() or generation != _generation:
		return
	_pending = false
	if result.has("balance"):
		phase = "paid"
	_publish()


func _bar_player() -> Player:
	return (_points[0].get_node("NetworkedEntity") as NetworkedInteraction).player_for_peer(worker)


func _publish() -> void:
	_publish_in = 0.25
	snapshot = {
		"worker": worker,
		"phase": phase,
		"left": maxi(0, ceili(DURATION - elapsed)),
		"dirty": dirty.duplicate(),
		"orders": orders.duplicate(),
		"cargo": cargo,
		"cleared": cleared,
		"served": served
	}


func _present() -> void:
	if snapshot != _last_snapshot:
		_last_snapshot = snapshot.duplicate(true)
		for point: Node3D in _points:
			point.call("present", snapshot)
	var held := int(snapshot.get("cargo", -1))
	var player := (_points[0].get_node("NetworkedEntity") as NetworkedInteraction).player_for_peer(
		int(snapshot.get("worker", 0))
	)
	_carry.visible = held != -1 and player != null
	if _carry.visible:
		_carry.get_node("Empty").visible = held == -2
		_carry.get_node("Drink").visible = held >= 0
		_carry.global_transform = HeldItemPose.player_mount(player, Vector3(-0.10, -0.23, -0.5))
		var body := player.get_node("Body") as Node3D
		if not player.is_local() or body.visible:
			# Use the offhand side rather than overlap the ordinary inventory hand.
			_carry.global_position += (_carry.global_basis * Vector3(-0.44, 0, 0))


func _disconnect(peer: int) -> void:
	if entity.is_authority() and peer == worker:
		_reset(Network.mode)


func _death(peer: int, _attacker: int) -> void:
	if entity.is_authority() and peer == worker and phase == "active":
		_finish("failed")


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	worker = 0
	phase = "idle"
	dirty.clear()
	orders.clear()
	cargo = -1
	_player = null
	_pending = false
	_publish()
