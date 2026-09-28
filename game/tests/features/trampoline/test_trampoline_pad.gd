extends GutTest
## Bounce behavior for the trampoline pad (features/trampoline/trampoline_pad.gd).
## Runs single-process like test_combat.gd, so peer 1 is the local/server player and
## a player with authority 1 is what `is_local()` sees on the owning peer.

const PadScene := preload("res://features/trampoline/trampoline_pad.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const TrampolineBounce := preload("res://features/trampoline/trampoline_bounce.gd")

var _pad: StaticBody3D


func before_each() -> void:
	_pad = PadScene.instantiate() as StaticBody3D
	add_child_autofree(_pad)


func test_launches_the_local_player_standing_on_it() -> void:
	var player := _spawn_player(1)
	player.global_position = Vector3(0, 0.5, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(player.velocity.y, TrampolineBounce.BASE_LAUNCH_M_S * 0.5)


func test_does_not_touch_a_remote_players_velocity() -> void:
	var player := _spawn_player(2)
	player.velocity.y = 0.0
	player.global_position = Vector3(0, 0.5, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(player.velocity.y, 0.0)


func _spawn_player(authority: int) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.name = str(authority)
	player.set_multiplayer_authority(authority)
	add_child_autofree(player)
	return player
