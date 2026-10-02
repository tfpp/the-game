extends GutTest
## Song requests on the server: range, cooldown, a downed band, rotation and resets.

const FEATURE := preload("res://features/mariachi_band/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _band: MariachiBand
var _entity: NetworkedInteraction


func before_each() -> void:
	_band = FEATURE.instantiate() as MariachiBand
	add_child_autofree(_band)
	_band.set_process(false)
	_entity = _band.get_node("NetworkedEntity") as NetworkedInteraction
	await wait_process_frames(2)


func _player(peer: int, offset: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.net_position = _band.to_global(offset)
	return player


func _musicians() -> Array[StationaryPatron]:
	var list: Array[StationaryPatron] = []
	for node: Node in _band.get_node("Musicians").get_children():
		list.append(node as StationaryPatron)
	return list


func test_band_is_an_interactable_with_five_killable_musicians() -> void:
	assert_true(_band.is_in_group(&"interactables"))
	assert_eq(_band.interaction_text(), "Request a song (next: Jarabe Tapatío)")
	var instruments: Array[int] = []
	for musician: StationaryPatron in _musicians():
		assert_true(musician.is_in_group(&"killable"), "%s takes gunfire" % musician.name)
		var body := musician.get_node("Body") as MariachiMusicianModel
		assert_not_null(body.avatar, "built on the player avatar rig")
		assert_eq(body.band, _band)
		instruments.append(body.instrument)
	instruments.sort()
	assert_eq(instruments, [0, 0, 1, 2, 3], "two trumpets, violin, vihuela and guitarrón")
	assert_eq(GpsCatalog.category_for(_musicians()[0]), "People")


func test_request_in_range_plays_the_next_song_for_everyone() -> void:
	_player(1, Vector3(0, 0.9, -4.0))
	var take := _band.net_take
	assert_eq(_entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_band.net_song, 1)
	assert_eq(_band.net_take, take + 1, "a new take restarts the song on every peer")
	await wait_process_frames(1)
	assert_eq((_band.get_node("NowPlaying") as Label3D).text, "Now playing: Jarabe Tapatío")
	assert_eq(_band.get_node("Audio").get("stream"), MariachiBand.STREAMS[1])
	assert_eq(_band.interaction_text(), "Request a song (next: La Cucaracha)")


func test_requests_from_afar_unknown_peers_or_with_payloads_are_denied() -> void:
	_player(1, Vector3(0, 0.9, -8.0))
	assert_eq(_entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED, "too far")
	assert_eq(_entity._evaluate(7, &"use", {}), NetworkedEntity.Result.DENIED, "no player")
	_player(2, Vector3(1.0, 0.9, -3.5))
	assert_eq(_entity._evaluate(2, &"use", {"song": 0}), NetworkedEntity.Result.DENIED)
	assert_eq(_band.net_song, 0)
	assert_eq(_entity._evaluate(2, &"use", {}), NetworkedEntity.Result.ACCEPTED)


func test_requests_share_a_cooldown_so_two_players_cannot_skip_twice() -> void:
	_player(1, Vector3(0, 0.9, -4.0))
	_player(2, Vector3(2.0, 0.9, -3.5))
	assert_eq(_entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_entity._evaluate(2, &"use", {}), NetworkedEntity.Result.COOLDOWN)
	assert_eq(_band.net_song, 1, "only one song change")
	(_entity._actions[&"use"] as NetworkedEntity.Action).next_msec = 0
	assert_eq(_entity._evaluate(2, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_band.net_song, 0, "wraps back to the first song")


func test_a_downed_band_takes_no_requests_and_goes_quiet() -> void:
	var player := _player(1, Vector3(0, 0.9, -4.0))
	var musicians := _musicians()
	for musician: StationaryPatron in musicians.slice(1):
		musician.take_hit(1)
	assert_true(_band.band_awake(), "one musician is enough")
	assert_true(_band.can_use(player))
	musicians[0].take_hit(1)
	assert_false(_band.band_awake())
	assert_false(_band.can_use(player))
	assert_eq(_entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_band._process(0.016)
	assert_true(_band.is_silenced(), "music pauses while everyone is down")
	musicians[2]._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	assert_true(_band.band_awake(), "back after the usual respawn")
	_band._process(0.016)
	assert_false(_band.is_silenced())


func test_server_moves_on_after_each_song_plays_through() -> void:
	var length := MariachiSongs.duration(0) * MariachiBand.PLAYS_PER_SONG
	_band._process(length - 0.1)
	assert_eq(_band.net_song, 0)
	_band._process(0.2)
	assert_eq(_band.net_song, 1)
	assert_almost_eq(_band.elapsed, 0.0, 0.0001)


func test_session_reset_starts_over_from_the_first_song() -> void:
	_band.advance()
	var take := _band.net_take
	_band._reset_session(Network.Mode.OFFLINE)
	assert_eq(_band.net_song, 0)
	assert_gt(_band.net_take, take)


func test_late_joiner_snapshot_shows_and_plays_the_current_song() -> void:
	var late := FEATURE.instantiate() as MariachiBand
	late.net_song = 1
	late.net_take = 5
	add_child_autofree(late)
	late.set_process(false)
	await wait_process_frames(1)
	assert_eq((late.get_node("NowPlaying") as Label3D).text, "Now playing: Jarabe Tapatío")
	assert_eq(late.get_node("Audio").get("stream"), MariachiBand.STREAMS[1])
	var sync := late.get_node("NetworkedEntity/Sync") as MultiplayerSynchronizer
	for property: NodePath in [NodePath(".:net_song"), NodePath(".:net_take")]:
		assert_true(sync.replication_config.has_property(property))
		assert_true(sync.replication_config.property_get_spawn(property), "sent to late joiners")


func test_musicians_hold_their_instruments_where_their_hands_can_reach() -> void:
	for musician: StationaryPatron in _musicians():
		var body := musician.get_node("Body") as MariachiMusicianModel
		body._update(0.1)
		for right: bool in [false, true]:
			var hand := body.hand_position(right)
			var shoulder := body.avatar.shoulder_position(right)
			assert_lt(hand.distance_to(shoulder), 0.7, "%s arm reaches" % musician.name)
			assert_between(hand.y - musician.global_position.y, 0.6, 1.9)
