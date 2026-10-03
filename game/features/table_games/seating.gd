class_name CrownTableSeating
extends FoodCourt
## Reuse the booth system's authority, player pinning, escape and lifecycle handling.
const CHAIR := preload("res://features/casino_props/props/dealer_chair.tscn")
const SEAT := preload("res://features/table_games/seat.gd")
var table: CrownGameTable


func _ready() -> void:
	table = get_parent() as CrownGameTable
	add_to_group(&"seating")
	for at: Vector3 in layout(table.game):
		var chair := CHAIR.instantiate() as StaticBody3D
		chair.name = "Chair%d" % seats.size()
		chair.position = at
		# Imported chair faces +Z; the seated avatar faces -Z.
		chair.rotation.y = atan2(-at.x, -at.z)
		add_child(chair)
		var seat := Node3D.new()
		seat.name = "Seat%d" % seats.size()
		seat.set_script(SEAT)
		seat.set("court", self)
		seat.set("index", seats.size())
		seat.position = at
		seat.rotation.y = chair.rotation.y + PI
		add_child(seat)
		seats.append(seat)
	var empty := PackedInt32Array()
	empty.resize(seats.size())
	net_seats = empty
	entity.register_action(&"sit", _may_sit, _sit)
	entity.register_action(&"stand", _may_stand, _stand)
	entity.session_reset.connect(_reset_session)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_connect_combat.call_deferred()


static func layout(kind: String) -> Array[Vector3]:
	match kind:
		"blackjack":
			return [
				Vector3(-1.5, 0, .55),
				Vector3(-.6, 0, 1.15),
				Vector3(.6, 0, 1.15),
				Vector3(1.5, 0, .55)
			]
		"poker":
			return [
				Vector3(-1.65, 0, .05),
				Vector3(-.65, 0, 1.12),
				Vector3(.65, 0, 1.12),
				Vector3(1.65, 0, .05)
			]
		"baccarat":
			return [
				Vector3(-1.5, 0, 1.25),
				Vector3(-.5, 0, 1.25),
				Vector3(.5, 0, 1.25),
				Vector3(1.5, 0, 1.25)
			]
		"video_poker":
			return [Vector3(0, 0, .95)]
	return []


func sit_position(index: int) -> Vector3:
	return seats[index].global_position + Vector3(0, .65, 0)


func stand_position(index: int) -> Vector3:
	var seat := seats[index]
	return seat.global_position + seat.global_basis.z * .85


func _may_sit(peer: int, payload: Dictionary) -> bool:
	for other: Node in get_tree().get_nodes_in_group(&"seating"):
		if other != self and bool(other.call("is_seated", peer)):
			return false
	return super._may_sit(peer, payload)


func _exit_tree() -> void:
	_release_pin(false)
