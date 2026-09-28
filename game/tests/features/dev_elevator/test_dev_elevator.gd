extends GutTest
## Server-authoritative teleport for the debug-only warp pad
## (features/dev_elevator/dev_elevator.gd). Runs single-process like
## test_garage_door.gd, so peer 1 is the server and direct calls resolve locally.

const FeatureScene := preload("res://features/dev_elevator/feature.tscn")
const SlumArrivalPoint := preload("res://features/dev_elevator/slum_arrival_point.gd")
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _pad: DevElevator


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	_pad = _root.get_node("Pad") as DevElevator


func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func test_can_use_requires_being_near() -> void:
	var near := _player_at(_pad.global_position)
	var far := _player_at(_pad.global_position + Vector3(10, 0, 0))
	assert_true(_pad.can_use(near))
	assert_false(_pad.can_use(far))


func test_using_the_pad_with_no_registered_destination_leaves_the_player_put() -> void:
	var player := _player_at(_pad.global_position)
	var start := player.net_position
	_pad.request_teleport()
	assert_true(player.net_position.is_equal_approx(start))


func test_using_the_pad_sends_the_player_to_the_registered_slum_arrival() -> void:
	var arrival := SlumArrivalPoint.new()
	arrival.position = Vector3(42, 3, -17)
	arrival.slum_name = "Test Slum"
	add_child_autofree(arrival)

	var player := _player_at(_pad.global_position)
	_pad.request_teleport()
	assert_true(player.net_position.is_equal_approx(arrival.global_position))


func test_a_distant_player_cannot_trigger_the_pad() -> void:
	var arrival := SlumArrivalPoint.new()
	add_child_autofree(arrival)
	var player := _player_at(_pad.global_position + Vector3(20, 0, 0))
	var start := player.net_position
	_pad.request_teleport()
	assert_true(player.net_position.is_equal_approx(start))
