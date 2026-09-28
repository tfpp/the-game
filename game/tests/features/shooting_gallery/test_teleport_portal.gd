extends GutTest
## Server-authoritative teleport behavior for features/shooting_gallery's entrance
## and exit arches (teleport_portal.gd). Runs single-process like
## test_elevator_cab.gd, so peer 1 is the server and direct calls resolve as if
## the request came from the server.

const PlayerScene := preload("res://core/player/player.tscn")

var _portal: TeleportPortal


func before_each() -> void:
	_portal = TeleportPortal.new()
	_portal.destination = Vector3(80, 1.2, 6)
	_portal.destination_yaw = 0.0
	add_child_autofree(_portal)


func _player_at(pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	player.position = pos
	player.net_position = pos
	add_child_autofree(player)
	return player


func test_can_use_within_range() -> void:
	var player := _player_at(_portal.global_position + Vector3(1, 0, 0))
	assert_true(_portal.can_use(player))


func test_cannot_use_out_of_range() -> void:
	var player := _player_at(_portal.global_position + Vector3(50, 0, 0))
	assert_false(_portal.can_use(player))


func test_request_teleport_moves_the_player_to_the_destination() -> void:
	var player := _player_at(_portal.global_position + Vector3(1, 0, 0))
	_portal.request_teleport()
	assert_true(player.global_position.is_equal_approx(_portal.destination))
	assert_almost_eq(player.net_yaw, _portal.destination_yaw, 0.001)


func test_request_teleport_ignores_a_player_out_of_range() -> void:
	var player := _player_at(_portal.global_position + Vector3(50, 0, 0))
	var before := player.global_position
	_portal.request_teleport()
	assert_true(player.global_position.is_equal_approx(before))


func test_is_in_the_interactables_group() -> void:
	assert_true(_portal.is_in_group(&"interactables"))
