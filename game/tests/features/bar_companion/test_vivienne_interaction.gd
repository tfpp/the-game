extends GutTest
## Exercise the public Use path rather than bypassing the interaction selector.

const BAR := preload("res://features/bar_companion/feature.tscn")
const APARTMENTS := preload("res://features/apartments/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const INTERACTION := preload("res://features/interaction/feature.tscn")
const SUBTITLES := preload("res://features/subtitles/feature.tscn")

var _bar: BarCompanion
var _home: Apartments
var _wallet: PlayerMoney
var _npc: Vivienne
var _player: Player
var _interaction: CanvasLayer
var _subs: Subtitles
var _device: Controls.Device
var _playing: bool


func before_each() -> void:
	_device = Controls.device
	_playing = Controls.playing
	Controls.device = Controls.Device.TOUCH
	Controls.playing = true
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 20000}
	_home = APARTMENTS.instantiate() as Apartments
	add_child_autofree(_home)
	_bar = BAR.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_bar.set_process(false)
	_npc = _bar.get_node("Vivienne") as Vivienne
	_npc.set_physics_process(false)
	_subs = SUBTITLES.instantiate() as Subtitles
	add_child_autofree(_subs)
	_subs.set_process(false)
	_player = PLAYER.instantiate() as Player
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_stand_near()
	_interaction = INTERACTION.instantiate() as CanvasLayer
	add_child_autofree(_interaction)


func after_each() -> void:
	Controls.device = _device
	Controls.playing = _playing
	Network.peer_accounts.clear()


func _stand_near() -> void:
	_player.net_position = _npc.global_position + Vector3(0, 0, 0.9)
	_player.global_position = _player.net_position


func _claim_room() -> void:
	_player.net_position = _home.get_node("Lobby/Desk").global_position + Vector3(0, 0, 1)
	assert_gt(_home.claim(1), 0)
	_stand_near()


func test_use_near_her_explains_missing_room_without_charging() -> void:
	assert_same(_interaction._find_target(), _npc, "not Celeste or the bartender")
	_interaction.use()
	assert_true(_subs.is_showing(), "reply stays readable without looking above her head")
	assert_eq(_subs.current_text(), "Vivienne: Get a room at Lily Apartments first, darling.")
	assert_eq(int(_wallet.balances[1]), 20000)
	assert_eq(_npc.net_escort, 0)
	assert_eq(_bar.rerolls_for(1), 0)


func test_use_with_room_but_no_money_reports_failure_then_allows_retry() -> void:
	_claim_room()
	_wallet.balances[1] = 100
	_interaction.use()
	assert_eq(_subs.current_text(), "Vivienne: You can't afford that")
	assert_eq(int(_wallet.balances[1]), 100)
	assert_eq(_npc.net_escort, 0)
	assert_eq(_bar.rerolls_for(1), 0)
	_wallet.balances[1] = 20000
	# Cooldowns use wall time; clear the accepted failed-payment request for this retry.
	(_npc.get_node("NetworkedEntity") as NetworkedInteraction)._actions[&"use"].next_msec = 0
	_interaction.use()
	assert_eq(_npc.net_escort, 1)
	assert_string_contains(_subs.current_text(), "Vivienne: Lead me to your room, unit 101.")


func test_public_use_pays_and_apartment_arrival_announces_lucky_night() -> void:
	_claim_room()
	_interaction.use()
	assert_eq(int(_wallet.balances[1]), 20000 - CharmMath.BASE_PRICE_CENTS)
	assert_eq(_npc.net_escort, 1)
	assert_eq(_bar.rerolls_for(1), 0, "hiring alone does not grant luck")
	assert_eq(_subs.current_text(), "Vivienne: Lead me to your room, unit 101.")
	# Use while already hired cannot charge twice or re-hire her.
	_npc.use()
	assert_eq(int(_wallet.balances[1]), 20000 - CharmMath.BASE_PRICE_CENTS)
	var room := _home.floor_for(1).to_global(Apartments.unit_bounds(_home.unit_for(1)).get_center())
	_player.net_position = room
	_player.global_position = room
	_npc._physics_process(0.1)
	assert_eq(_subs.current_text(), "Vivienne: Lady Luck is on your side tonight.")
	assert_eq(_bar.rerolls_for(1), CharmMath.LUCK_REROLLS)
	assert_eq(_bar.luck_seconds_for(1), int(CharmMath.LUCK_S))
	assert_eq(_bar.rerolls_for(2), 0)
	_npc._physics_process(Vivienne.LINGER_S + 0.1)
	assert_eq(_npc.net_escort, 0)


func test_far_unknown_and_forged_use_do_not_show_dialogue_or_charge() -> void:
	var talk := _npc.get_node("NetworkedEntity") as NetworkedInteraction
	_player.net_position += Vector3(0, 0, 10)
	_player.global_position = _player.net_position
	_npc.use()
	assert_false(_subs.is_showing())
	assert_eq(talk._evaluate(9, &"use", {}), NetworkedEntity.Result.DENIED)
	_stand_near()
	assert_eq(talk._evaluate(1, &"use", {"peer": 2}), NetworkedEntity.Result.DENIED)
	assert_false(_subs.is_showing())
	assert_eq(int(_wallet.balances[1]), 20000)
	assert_eq(_npc.net_escort, 0)
