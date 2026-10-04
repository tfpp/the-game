extends GutTest

const DESK := preload("res://features/irs_desk/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _desk: Node3D
var _player: Player
var _wallet: PlayerMoney
var _entity: NetworkedInteraction
var _menu: CanvasLayer


func before_each() -> void:
	_desk = DESK.instantiate() as Node3D
	add_child_autofree(_desk)
	_entity = _desk.get_node("NetworkedEntity")
	_menu = _desk.get_node("TaxForm")
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _desk.global_position + Vector3(0, 0.9, -1.2)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 2000}


func after_each() -> void:
	_menu._close()
	await get_tree().process_frame


func _payload(winnings: int, tax: int) -> Dictionary:
	return {"token": _menu._token, "winnings": winnings, "tax": tax}


func _submit(winnings: int, tax: int) -> NetworkedEntity.Result:
	return _entity._evaluate(1, &"file", _payload(winnings, tax))
