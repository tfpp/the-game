extends GutTest
## Mitch McConnell, his intern, the peace sign and Trump's head pat.

const FEATURE := preload("res://features/casino_patrons/feature.tscn")
const SUBTITLES := preload("res://features/subtitles/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _feature: Node3D
var _mitch: Mitch
var _trump: Trump
var _subtitles: Subtitles


func before_each() -> void:
	_subtitles = SUBTITLES.instantiate()
	add_child_autofree(_subtitles)
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_mitch = _feature._spawn_patron({"index": PatronModel.MITCH_LOOK})
	_trump = _feature._spawn_patron({"index": PatronModel.TRUMP_LOOK})
	_feature.get_node("Patrons").add_child(_mitch)
	_feature.get_node("Patrons").add_child(_trump)
	_mitch.set_physics_process(false)
	_trump.set_physics_process(false)


func test_spawns_on_his_route_with_wheelchair_and_intern() -> void:
	assert_eq(_mitch.name, "Patron%d" % PatronModel.MITCH_LOOK)
	assert_eq(_mitch.position, PatronMath.MITCH_ROUTE[0])
	assert_eq(_mitch.route.size(), PatronMath.MITCH_ROUTE.size())
	assert_eq((_mitch.get_node("Body/NameTag") as Label3D).text, "Mitch McConnell")
	assert_not_null(_mitch.find_child("Wheelchair", true, false))
	var intern := _mitch.get_node("Body/Intern") as PatronModel
	assert_gt(intern.position.z, 0.5, "The intern pushes from behind (+Z)")
	assert_not_null(intern.find_child("LongHair", true, false))
	assert_null(intern.find_child("NameTag", true, false))


func test_sits_in_the_chair_and_intern_holds_handles() -> void:
	_mitch._process(0.1)
	var model := _mitch.get_node("Body") as MitchModel
	var hips := model.get_node("Hips") as Node3D
	assert_almost_eq(hips.position.y, MitchModel.SEAT_Y + 0.08, 0.01)
	var hand := model.get_node("Intern").find_child("HandR", true, false) as Node3D
	var handle := model.find_child("HandleR", true, false) as Node3D
	var local_hand := model.to_local(hand.global_position)
	var local_handle := model.to_local(handle.global_position)
	assert_lt(local_hand.distance_to(local_handle), 0.25, "%s vs %s" % [local_hand, local_handle])


func test_peace_sign_raises_the_hand_for_everyone() -> void:
	var model := _mitch.get_node("Body") as MitchModel
	var fingers := model.find_child("PeaceSign", true, false) as Node3D
	_mitch._process(0.1)
	assert_false(fingers.visible)
	var resting := (model.find_child("HandR", true, false) as Node3D).global_position.y
	_mitch._throw_peace_sign()
	for i: int in 10:
		_mitch._process(0.05)
	assert_true(_mitch.is_throwing_peace_sign())
	assert_true(fingers.visible)
	assert_gt((model.find_child("HandR", true, false) as Node3D).global_position.y, resting + 0.4)
	for i: int in 80:
		_mitch._process(0.05)
	assert_false(fingers.visible)


func test_server_throws_peace_sign_on_a_timer() -> void:
	_mitch._peace_timer = 0.01
	_mitch._physics_process(0.02)
	assert_true(_mitch.is_throwing_peace_sign())
	assert_between(_mitch._peace_timer, Mitch.PEACE_MIN_S, Mitch.PEACE_MAX_S)


func test_can_pat_range() -> void:
	assert_true(Trump.can_pat(Vector3(8.5, -1.5, 0), Vector3(8.5, -1.5, -0.8)))
	assert_false(Trump.can_pat(Vector3(8.5, -1.5, 0), Vector3(8.5, -1.5, -1.5)))


func test_trump_pats_mitch_when_close_and_says_good_boy() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = _trump.global_position + Vector3(3, 0, 0)
	_mitch.position = _trump.position + Vector3(0, 0, -0.5)
	_trump._try_pat()
	assert_true(_trump.is_patting())
	assert_eq(_mitch._pause, Trump.PAT_HOLD_S, "Mitch stops for his pat")
	assert_true(_subtitles._label.text.contains("Good boy."))
	_trump._process(0.1)
	assert_true((_trump.get_node("SpeechBubble") as Label3D).visible)
	_trump._patting = 0.0
	_trump._try_pat()
	assert_false(_trump.is_patting(), "Cooldown prevents an immediate second pat")


func test_no_pat_when_far_or_knocked_down() -> void:
	_mitch.position = _trump.position + Vector3(0, 0, -3)
	_trump._try_pat()
	assert_false(_trump.is_patting())
	_mitch.position = _trump.position + Vector3(0, 0, -0.5)
	_mitch.net_ragdoll = true
	_trump._try_pat()
	assert_false(_trump.is_patting())
