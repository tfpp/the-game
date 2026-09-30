extends GutTest
## A wallet landing on $67 (cents ignored) makes every player do the 6-7 emote.

const PLAYER := preload("res://core/player/player.tscn")
const MONEY := preload("res://features/money/feature.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")
const VIEW := preload("res://features/player_models/emote_view.gd")

var _money: PlayerMoney
var _models: PlayerModels


func before_each() -> void:
	for peer: int in [1, 2, 3]:
		var player := PLAYER.instantiate() as Player
		player.name = str(peer)
		player.set_multiplayer_authority(peer)
		add_child_autofree(player)
		player.set_physics_process(false)
		player.set_process(false)
	_models = MODELS.instantiate() as PlayerModels
	add_child_autofree(_models)
	_models.set_process(false)
	_money = MONEY.instantiate() as PlayerMoney
	add_child_autofree(_money)
	_money.set_process(false)


func after_each() -> void:
	await get_tree().process_frame


func test_only_whole_dollar_sixty_seven_counts() -> void:
	assert_true(PlayerMoney.lands_on_six_seven(null, 6700))
	assert_true(PlayerMoney.lands_on_six_seven(6699, 6799))
	assert_true(PlayerMoney.lands_on_six_seven(10000, 6742))
	assert_false(PlayerMoney.lands_on_six_seven(6700, 6799), "already $67")
	assert_false(PlayerMoney.lands_on_six_seven(6000, 6800))
	assert_false(PlayerMoney.lands_on_six_seven(6000, 6699))
	assert_false(PlayerMoney.lands_on_six_seven(6000, 670))
	assert_false(PlayerMoney.lands_on_six_seven(0, -6700))


func test_landing_on_sixty_seven_makes_everyone_emote() -> void:
	_money._set_balance(2, 5000)
	assert_true(_models.emotes.is_empty())
	_models.emote_clock = 4.0
	_money._set_balance(2, 6755)
	assert_eq(_models.emotes.size(), 3)
	for peer: int in [1, 2, 3]:
		assert_eq(_models.emote_name(peer), PlayerModels.SIX_SEVEN)
		assert_eq(float(_models.emotes[peer]["started"]), 4.0)
	assert_gt(_models.emote_weight(1), -1.0)


func test_staying_at_sixty_seven_does_not_retrigger() -> void:
	_money._set_balance(2, 6700)
	_models.emotes = {}
	_money._set_balance(2, 6750)
	assert_true(_models.emotes.is_empty())
	_money._set_balance(2, 6800)
	_money._set_balance(2, 6700)
	assert_eq(_models.emotes.size(), 3)


func test_emote_expires_and_view_plays_six_seven() -> void:
	_models._process(0)
	_models.emote_everyone()
	_models.emote_clock = 1.0
	var avatar := get_node("1/Body/Avatar") as BlockPlayerModel
	var hand := avatar.human.skeleton.find_bone("HandL")
	var before := avatar.human.skeleton.get_bone_global_pose(hand).origin
	var view := _models.get_node("EmoteView")
	view._process(0)
	assert_true(avatar.human.visible)
	assert_ne(avatar.human.skeleton.get_bone_global_pose(hand).origin, before)
	_models.emote_clock = PlayerModels.EMOTE_SECONDS + 0.5
	_models._expire_emotes()
	assert_true(_models.emotes.is_empty())


func test_bob_alternates_hands() -> void:
	assert_almost_eq(VIEW.six_seven_bob(0.0), 0.0, 0.001)
	assert_gt(VIEW.six_seven_bob(0.125), 0.0)
	assert_lt(VIEW.six_seven_bob(0.375), 0.0)


func test_clients_cannot_request_six_seven() -> void:
	assert_eq(
		_models.entity._evaluate(1, &"emote", {"name": PlayerModels.SIX_SEVEN}),
		NetworkedEntity.Result.DENIED
	)
