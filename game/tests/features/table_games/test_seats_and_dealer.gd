extends GutTest
const SUITES := preload("res://features/table_games/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var suites: Node3D
var table: CrownGameTable
var seats: CrownTableSeating
var player: Player


func before_each() -> void:
	suites = SUITES.instantiate()
	var dealer := suites.get_node("Room/Poker/Dealer") as CrownDealer
	dealer.preview_on_server = true
	add_child_autofree(suites)
	(suites.get_node("Room") as StreamedRoom).load_room(60000)
	table = suites.get_node("Room/Poker") as CrownGameTable
	table.set_process(false)
	seats = table.get_node("Seats") as CrownTableSeating
	seats.set_physics_process(false)
	player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = seats.seats[0].global_position + Vector3.UP * .9144
	player.global_position = player.net_position


func test_seat_claim_validation_and_cross_system_exclusivity() -> void:
	assert_eq(seats.seats.size(), 4)
	assert_false(seats._may_sit(1, {"seat": -1}))
	assert_false(seats._may_sit(1, {"seat": 9}))
	assert_false(seats._may_sit(1, {"seat": 0, "peer": 2}))
	assert_true(seats._may_sit(1, {"seat": 0}))
	assert_true(seats._sit(1, {"seat": 0}))
	assert_false(seats._may_sit(2, {"seat": 0}), "An occupied seat cannot be claimed")
	var other := suites.get_node("Room/Blackjack/Seats") as CrownTableSeating
	player.net_position = other.seats[0].global_position
	assert_false(other._may_sit(1, {"seat": 0}), "One peer can occupy only one seating system")
	assert_true(seats._stand(1, {}))
	assert_true(other._may_sit(1, {"seat": 0}))
	player.net_position += Vector3.RIGHT * 20
	assert_false(other._may_sit(1, {"seat": 0}), "Distant seat claims fail")


func test_local_pin_stand_disconnect_and_teleport_release() -> void:
	seats._sit(1, {"seat": 0})
	seats._update_local_pin(0)
	assert_eq(player.global_position, seats.sit_position(0))
	assert_false(player.is_physics_processing())
	var avatar := BlockPlayerModel.new()
	avatar.player = player
	player.add_child(avatar)
	avatar._process(0)
	assert_true(avatar.seated, "Avatar discovers tables after other seating group members")
	seats._stand(1, {})
	seats._update_local_pin(0)
	assert_true(player.is_physics_processing())
	assert_gt(player.global_position.distance_to(seats.sit_position(0)), .8)
	seats._sit(1, {"seat": 1})
	seats._on_peer_disconnected(1)
	assert_false(seats.is_seated(1))
	seats._sit(1, {"seat": 0})
	player.net_position = Vector3.ZERO
	seats._release_moved_players()
	assert_false(seats.is_seated(1))
	seats._sit(1, {"seat": 0})
	seats._reset_session(Network.Mode.OFFLINE)
	assert_false(seats.is_seated(1))


func test_layout_preserves_dealer_side_and_room_aisles() -> void:
	for name: String in ["Blackjack", "Poker", "Baccarat", "VideoPoker"]:
		var target := suites.get_node("Room/" + name) as CrownGameTable
		var sitting := target.get_node("Seats") as CrownTableSeating
		assert_eq(sitting.seats.size(), 1 if name == "VideoPoker" else 4)
		for seat: Node3D in sitting.seats:
			assert_gt(seat.position.z, 0.0, "Dealer edge stays open")
			var gaze := -seat.basis.z
			assert_gt(gaze.dot((-seat.position).normalized()), .99, "Chairs face the felt")
	assert_eq((suites.get_node("Room/Craps/Seats") as CrownTableSeating).seats.size(), 0)


func test_dealer_queue_clock_and_late_join_seek_real_bones() -> void:
	var dealer := table.get_node("Dealer") as CrownDealer
	dealer.set_process(false)
	table._animate_dealer(["shuffle", "deal"])
	table._update_dealer_clock(2.9)
	dealer._process(0)
	assert_eq(dealer.current_motion, "deal", "Late observer seeks past the completed shuffle")
	var skeleton := dealer.model.human.skeleton
	var wrist := skeleton.find_bone("HandR")
	var first := skeleton.get_bone_global_pose(wrist).origin
	table._update_dealer_clock(.45)
	dealer._process(0)
	var second := skeleton.get_bone_global_pose(wrist).origin
	assert_gt(first.distance_to(second), .015, "Authored dealing moves the real skinned wrist")
	table._update_dealer_clock(20)
	dealer._process(0)
	assert_eq(dealer.current_motion, "idle")
	table._animate_dealer(["greet"])
	dealer._process(0)
	assert_eq(dealer.current_motion, "greet", "New action starts from zero after an idle gap")
	for clip: StringName in CrownDealer.CLIPS.get_animation_list():
		var animation := CrownDealer.CLIPS.get_animation(clip)
		assert_gt(animation.get_track_count(), 30, "Includes torso, head, limbs and finger tracks")
		assert_gt(animation.length, 1.0)


func test_dealer_actions_append_without_disclosing_private_cards() -> void:
	table._animate_dealer(["shuffle", "deal"])
	table._update_dealer_clock(.5)
	table._animate_dealer(["reveal", "collect", "payout"])
	var cue: Dictionary = table.state["dealer_animation"]
	assert_eq(cue["queue"], ["shuffle", "deal", "reveal", "collect", "payout"])
	assert_almost_eq(float(cue["elapsed"]), .5, .001)
	assert_false(cue.has("cards"))
	table._update_dealer_clock(30)
	var stamp := float(table.state["dealer_animation"]["elapsed"])
	table._update_dealer_clock(30)
	assert_eq(
		float(table.state["dealer_animation"]["elapsed"]),
		stamp,
		"Completed queues stop network clock churn"
	)
