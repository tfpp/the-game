extends GutTest
## The penguin's wife (features/penguin/feature.tscn's Wife instance): her looks,
## her out-of-phase patrol and the couple reaction. Single-process like
## test_penguin.gd, so peer 1 is the server.
##
## Physics is frozen in before_each and driven through manual `_physics_process`
## calls: AnimatableBody3D transform sets outside the physics step are unreliable
## in headless runs, so assertions use the replicated plain vars (net_position,
## net_yaw, _angle) and net_position-based reactions instead of the body transform.

const FeatureScene := preload("res://features/penguin/feature.tscn")

const HUSBAND_HOME := Vector3(-26, 0.4, 8)
const WIFE_HOME := Vector3(-23.8, 0.4, 12.3)

var _feature: Node3D
var _husband: Penguin
var _wife: Penguin


func before_each() -> void:
	_feature = FeatureScene.instantiate() as Node3D
	add_child_autofree(_feature)
	_husband = _feature.get_node("Penguin") as Penguin
	_wife = _feature.get_node("Wife") as Penguin
	_husband.set_physics_process(false)
	_wife.set_physics_process(false)
	await get_tree().physics_frame


func test_the_wife_is_a_distinct_named_penguin() -> void:
	assert_eq(_husband.display_name, "Penguin")
	assert_eq(_wife.display_name, "Penguin's wife")
	assert_false(_husband.is_wife)
	assert_true(_wife.is_wife)
	assert_eq(GpsCatalog.label_for(_husband), "Penguin")
	assert_eq(GpsCatalog.label_for(_wife), "Penguin's wife")
	assert_eq(GpsCatalog.category_for(_wife), "Animals")


func test_the_wife_wears_a_bow_and_blush() -> void:
	assert_false(
		(_husband.get_node("Body/Torso/Bow") as Node3D).visible, "The husband wears no bow"
	)
	assert_true((_wife.get_node("Body/Torso/Bow") as Node3D).visible, "The wife wears a bow")
	assert_true(
		(_wife.get_node("Body/Torso/Bow/BlushLeft") as MeshInstance3D).is_visible_in_tree(),
		"The wife has blush",
	)
	assert_lt(_wife.scale.x, _husband.scale.x, "The wife is the smaller penguin")


func test_the_couple_shares_one_patrol_contract() -> void:
	assert_eq(_wife._home, WIFE_HOME, "Her circle is centered on her own spot")
	assert_eq(_husband._home, HUSBAND_HOME)
	assert_almost_eq(_wife.start_angle, PI, 0.01, "Out of phase with her husband's 0")
	assert_almost_eq(_husband.start_angle, 0.0, 0.01)
	var gap := WIFE_HOME.distance_to(HUSBAND_HOME) - 2.0 * PenguinWaddle.PATROL_RADIUS
	assert_gt(gap, 0.57, "Beak-to-beak, but their bodies never overlap")
	assert_lt(gap, PenguinWaddle.COUPLE_RADIUS, "Close enough for the happy reaction")


func test_the_wife_patrols_her_own_circle() -> void:
	assert_almost_eq(_wife._angle, _wife.start_angle, 0.01)
	_wife._physics_process(0.25)
	var expected_angle := (
		_wife.start_angle
		+ PenguinWaddle.angular_speed(PenguinWaddle.PATROL_RADIUS, PenguinWaddle.WALK_SPEED) * 0.25
	)
	assert_almost_eq(_wife._angle, expected_angle, 0.001)
	assert_eq(
		_wife.net_position,
		PenguinWaddle.position_on_circle(WIFE_HOME, PenguinWaddle.PATROL_RADIUS, expected_angle),
		"She circles her own home, not her husband's",
	)
	assert_almost_eq(
		_wife.net_yaw, PenguinWaddle.facing_yaw(expected_angle), 0.001, "Beak along travel"
	)


func test_the_couple_reacts_when_they_meet() -> void:
	# No player-models node exists here, so only the spouse can trigger the reaction.
	_husband.net_position = Vector3(-26, 0.4, 8)
	_wife.net_position = Vector3(-27, 0.4, 8.5)
	for penguin: Penguin in [_husband, _wife]:
		assert_true(penguin._near_spouse(), "Spouse within %sm" % PenguinWaddle.COUPLE_RADIUS)
		penguin._elapsed = 0.1
		penguin._process(0.0)
		assert_gt(penguin._body.position.y, 0.0, "Hops when the spouse is close")
		assert_ne(penguin._wave_flipper.rotation.z, 0.0, "Waves at the spouse")


func test_the_couple_calm_down_when_apart() -> void:
	_husband.net_position = Vector3(-26, 0.4, 8)
	_wife.net_position = Vector3(-26, 0.4, 18)
	_husband._elapsed = 0.1
	_husband._process(0.0)
	assert_false(_husband._near_spouse())
	assert_eq(_husband._body.position.y, 0.0, "No spouse within range")
	assert_eq(_husband._wave_flipper.rotation.z, 0.0)


func test_a_dead_spouse_gets_no_reaction() -> void:
	_husband.net_position = Vector3(-26, 0.4, 8)
	_wife.net_position = Vector3(-27, 0.4, 8.5)
	_wife.net_alive = false
	assert_false(_husband._near_spouse(), "He waits for her to respawn")


func test_the_wife_is_killable_and_respawns_at_home_in_phase() -> void:
	assert_true(_wife.is_in_group(&"killable"))
	_wife.take_hit(2)
	assert_false(_wife.net_alive)
	_wife._physics_process(Penguin.RESPAWN_DELAY_S)
	assert_true(_wife.net_alive)
	assert_eq(_wife.net_position, _wife._home, "Respawns at her own home")
	assert_almost_eq(_wife._angle, _wife.start_angle, 0.001, "Still out of phase")
