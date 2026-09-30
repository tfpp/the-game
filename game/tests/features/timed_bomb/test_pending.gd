extends GutTest

const BOMB := preload("res://features/timed_bomb/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _bomb: Node3D
var _player: Player


class SlowBomb:
	extends "res://features/timed_bomb/timed_bomb.gd"
	signal complete
	var calls := 0

	func _request(_guess: String) -> Dictionary:
		calls += 1
		await complete
		return {"state": "defused", "remaining": 100, "message": "Bomb defused."}


func before_each() -> void:
	_bomb = BOMB.instantiate()
	_bomb.set_script(SlowBomb)
	add_child_autofree(_bomb)
	_bomb.set_process(false)
	_bomb.net_state = "armed"
	_bomb.net_available = true
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _bomb.global_position + Vector3.UP


func test_pending_request_blocks_second_guess_and_commits_after_respawn() -> void:
	assert_eq(_guess(), NetworkedEntity.Result.ACCEPTED)
	assert_true(_bomb._busy)
	assert_eq(_guess(), NetworkedEntity.Result.COOLDOWN)
	assert_false(_bomb._may_defuse(1, {"code": "0042"}))
	assert_eq(_bomb.calls, 1)
	_player.net_position = Vector3(100, 100, 100)
	_bomb.complete.emit()
	assert_eq(_bomb.net_state, "defused")
	assert_false(_bomb._busy)


func test_disconnected_player_gets_no_reply_but_shared_defusal_commits() -> void:
	watch_signals(_bomb.entity)
	_guess()
	_player.free()
	_bomb.complete.emit()
	assert_eq(_bomb.net_state, "defused")
	assert_signal_not_emitted(_bomb.entity, "event_received")


func test_previous_session_http_completion_cannot_change_new_session() -> void:
	_guess()
	_bomb._reset(Network.Mode.OFFLINE)
	_bomb.complete.emit()
	assert_eq(_bomb.net_state, "loading")
	assert_false(_bomb.net_available)


func _guess() -> NetworkedEntity.Result:
	return _bomb.entity._evaluate(1, &"defuse", {"code": "0042"})
