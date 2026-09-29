extends GutTest
## Room cabinets idle in attract mode and only load a game once someone uses them.

const Scene := preload("res://features/scumm_arcade/cabinet.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var cabinet: ScummArcadeCabinet


func before_each() -> void:
	cabinet = Scene.instantiate() as ScummArcadeCabinet
	cabinet.room_only = true
	cabinet.position = ScummArcadeRoom.ORIGIN + Vector3(0, 0, -3.4)
	add_child_autofree(cabinet)
	cabinet.set_process(false)


func _player(peer: int, at: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = at
	player.net_position = at
	return player


func test_room_cabinet_waits_for_a_watcher_before_running() -> void:
	_player(1, ScummArcadeRoom.ARRIVAL)
	assert_false(cabinet._wants_runtime(), "Entering the room alone loads no interpreter")
	cabinet.request_watch()
	assert_true(cabinet._watchers.has(1))
	assert_true(cabinet._has_audience(), "Using a cabinet starts its game on the server")


func test_watch_requests_are_validated_and_expire_outside_the_room() -> void:
	var player := _player(1, ScummArcadeRoom.ENTRANCE + Vector3(0, 0.95, 2))
	cabinet.request_watch()
	assert_false(cabinet._has_audience(), "Players outside the room cannot start a cabinet")
	player.net_position = ScummArcadeRoom.ARRIVAL
	cabinet.request_watch()
	assert_true(cabinet._has_audience())
	player.net_position = ScummArcadeRoom.ENTRANCE
	assert_false(cabinet._has_audience(), "Leaving the room returns the cabinet to attract mode")
	assert_true(cabinet._watchers.is_empty())
	player.net_position = ScummArcadeRoom.ARRIVAL
	assert_false(cabinet._has_audience(), "Coming back needs another use")


func test_disconnect_forgets_the_watcher() -> void:
	_player(1, ScummArcadeRoom.ARRIVAL)
	cabinet.request_watch()
	cabinet._peer_left(1)
	assert_false(cabinet._has_audience())


func test_attract_screen_prompts_then_shows_loading() -> void:
	cabinet._ensure_view()
	var view := cabinet._view
	assert_eq(view.attract_text(), "PRESS USE TO PLAY")
	assert_true(view._sign.visible)
	cabinet._engaged = true
	assert_eq(view.attract_text(), "LOADING GAME...")
	view.set_screen(ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8)))
	assert_false(view._attract.visible, "The live game replaces attract mode")
	view.show_attract()
	assert_true(view._sign.visible)
	assert_null(view._screen_material.albedo_texture)


func test_display_cabinet_invites_watching() -> void:
	cabinet.game_id = "tentacle"
	cabinet._ensure_view()
	assert_eq(cabinet._view.attract_text(), "PRESS USE TO WATCH")
