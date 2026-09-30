class_name WallGun
extends Node3D
## One gun hanging on the pawn shop wall (or the top hat on its stand). Use buys a
## copy of it through the shared wallet (`PlayerMoney.charge`) and hands it over with
## `PlayerInventory.collect`; the wall keeps unlimited stock, so nothing about the rack
## itself is replicated.

const SPEAKER := "Rusty Hogg"

## Which holdables ItemCatalog weapon hangs here.
@export var item_id := "pistol"
@export var price_cents := 1000
## Where the price tag hangs relative to the item (the hat stand puts it above the hat).
@export var tag_position := Vector3(0, -0.32, 0.05)

var _busy: Dictionary[int, bool] = {}
var _generation := 0

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	var view := ItemCatalog.create_view(item_id)
	if view != null:
		view.name = "View"
		# Hung sideways, muzzle pointing along the wall.
		view.rotation.y = PI * 0.5
		add_child(view)
	var tag := Label3D.new()
	tag.name = "PriceTag"
	tag.text = "%s\n%s" % [_display_name(), PlayerMoney.format_money(price_cents)]
	tag.font_size = 20
	tag.outline_size = 6
	tag.pixel_size = 0.005
	tag.modulate = Color(1, 0.84, 0.4)
	tag.double_sided = false
	tag.position = tag_position
	add_child(tag)
	entity.register_use(can_use, _buy)
	entity.event_received.connect(_on_event)
	entity.session_reset.connect(_reset)


func interaction_text() -> String:
	return "Buy %s — %s" % [_display_name(), PlayerMoney.format_money(price_cents)]


func can_use(player: Player) -> bool:
	if not entity.in_range(player):
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and hand.inventory().can_collect(item_id)


func use() -> void:
	entity.request_use()


func _buy(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if wallet == null or holdables == null or _busy.has(peer):
		return false
	_busy[peer] = true
	_charge(wallet, holdables, player, peer)
	return true


func _charge(wallet: PlayerMoney, holdables: Node, player: Player, peer: int) -> void:
	var generation := _generation
	var hand := Hand.for_peer(get_tree(), peer)
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, price_cents)
	if generation != _generation or not is_inside_tree():
		return
	_busy.erase(peer)
	var same_player := is_instance_valid(player) and entity.player_for_peer(peer) == player
	if result.has("error"):
		if same_player:
			_say(peer, "%s. Come back with more cash." % str(result["error"]))
		return
	var delivered := false
	if same_player and is_instance_valid(hand) and Hand.for_peer(get_tree(), peer) == hand:
		delivered = hand.inventory().collect(item_id)
	# A paid gun is never lost: if the bag filled or the buyer left mid-payment it
	# lands on the shop floor as an ordinary pickup.
	if not delivered and is_instance_valid(holdables):
		var spot := global_position + global_basis.z.normalized() * 1.2
		spot.y = 0.0
		holdables.call(&"spawn_thrown_item", item_id, spot + Vector3.UP, spot)
	if same_player:
		var line := "Pleasure doing business." if delivered else "It's on the floor, friend."
		_say(
			peer,
			"%s for the %s. %s" % [PlayerMoney.format_money(price_cents), _display_name(), line]
		)


func _say(peer: int, text: String) -> void:
	entity.send_event(&"receipt", {"text": text}, peer)


func _on_event(event: StringName, payload: Dictionary) -> void:
	if event == &"receipt":
		Subtitles.say(get_tree(), SPEAKER, str(payload.get("text", "")))


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_busy.clear()


func _display_name() -> String:
	var def := ItemCatalog.find(item_id)
	return def.display_name if def != null else item_id
