extends GutTest

const Story := preload("res://features/adventure_machine/story.gd")
const SOLUTION: Array[String] = [
	"go_tavern",
	"take_cracker",
	"learn",
	"go_quay",
	"feed",
	"take_magnet",
	"go_shop",
	"buy_rope",
	"combine",
	"go_quay",
	"fish",
	"go_fort",
	"challenge",
	"retort_0",
	"retort_1",
	"retort_2",
	"unlock",
	"go_quay",
	"sail"
]


func _complete(story: Story) -> void:
	for id: String in SOLUTION:
		assert_true(story.choose(id), id)


func test_complete_original_adventure_has_ending_and_no_real_rewards() -> void:
	var story := Story.new()
	_complete(story)
	assert_true(story.won)
	assert_true(story.gate_open)
	assert_eq(story.inventory, ["fishing", "key", "bell"])
	assert_eq(story.revision, SOLUTION.size())
	assert_string_contains(story.page()["message"], "THE END")
	assert_false(story.allows("sail"), "An ending cannot be won repeatedly")
	assert_true(story.allows("restart"))


func test_impossible_item_actions_do_not_skip_puzzles_or_duplicate_items() -> void:
	var story := Story.new()
	for id: String in ["unlock", "sail", "feed", "fish", "combine", "retort_0", "go_secret"]:
		assert_false(story.choose(id), id)
	assert_eq(story.revision, 0)
	assert_eq(story.inventory.size(), 0)
	assert_true(story.choose("take_magnet"))
	assert_false(story.choose("take_magnet"))
	assert_eq(story.inventory, ["magnet"])
	assert_true(story.choose("go_tavern"))
	assert_true(story.choose("take_cracker"))
	assert_false(story.choose("take_cracker"))
	assert_false(story.choose("feed"), "Items must be used at their actual target")
	assert_true(story.choose("go_quay"))
	assert_true(story.choose("feed"))
	assert_false(story.choose("feed"))
	assert_false(story.allows("gull"))


func test_duel_requires_learning_and_wrong_answers_or_retreat_never_softlock() -> void:
	var story := Story.new()
	assert_true(story.choose("go_fort"))
	assert_true(story.choose("challenge"))
	assert_eq(story.duel, -1)
	assert_string_contains(story.message, "tavern")
	assert_true(story.choose("go_quay"))
	assert_true(story.choose("go_tavern"))
	assert_true(story.choose("learn"))
	assert_true(story.choose("go_quay"))
	assert_true(story.choose("go_fort"))
	assert_true(story.choose("challenge"))
	assert_false(story.choose("go_quay"), "The duel has explicit retreat, not a hidden exit")
	assert_true(story.choose("retort_2"))
	assert_eq(story.duel, 0)
	assert_true(story.choose("hint"))
	assert_string_contains(story.message, Story.RETORTS[0])
	assert_true(story.choose("retort_0"))
	assert_true(story.choose("retreat"))
	assert_eq(story.duel, -1)
	assert_true(story.choose("challenge"))
	for index: int in 3:
		assert_true(story.choose("retort_%d" % index))
	assert_true(story.gate_open)
	assert_false(story.allows("challenge"))
	assert_false(story.allows("unlock"), "A verbal victory doesn't invent the locker key")


func test_puzzles_can_be_solved_in_a_different_order() -> void:
	var story := Story.new()
	var route: Array[String] = [
		"take_magnet",
		"go_tavern",
		"learn",
		"go_quay",
		"go_fort",
		"challenge",
		"retort_0",
		"retort_1",
		"retort_2",
		"go_quay",
		"go_tavern",
		"take_cracker",
		"go_quay",
		"feed",
		"go_shop",
		"buy_rope",
		"combine",
		"go_quay",
		"fish",
		"go_fort",
		"unlock",
		"go_quay",
		"sail"
	]
	for id: String in route:
		assert_true(story.choose(id), id)
	assert_true(story.won)


func test_restart_confirmation_cancel_and_replay_preserve_monotonic_revision() -> void:
	var story := Story.new()
	_complete(story)
	assert_true(story.choose("restart"))
	assert_true(story.won, "First press does not erase anything")
	assert_false(story.allows("take_magnet"))
	assert_true(story.choose("cancel_restart"))
	assert_true(story.won)
	assert_true(story.choose("restart"))
	var revision := story.revision
	assert_true(story.choose("confirm_restart"))
	assert_eq(story.revision, revision + 1, "Old pre-restart commands stay stale")
	assert_false(story.won)
	assert_false(story.learned)
	assert_false(story.gate_open)
	assert_false(story.fed_gull)
	assert_false(story.bought_rope)
	assert_eq(story.inventory.size(), 0)
	assert_eq(story.room, "quay")
	_complete(story)
	assert_true(story.won)


func test_hints_snapshots_and_history_are_bounded_and_independent() -> void:
	var first := Story.new()
	var other := Story.new()
	assert_true(first.choose("hint"))
	assert_string_contains(first.message, "Wake")
	for id: String in SOLUTION:
		assert_true(first.choose(id), id)
		if first.allows("hint"):
			assert_true(first.choose("hint"))
			assert_false(first.message.is_empty())
		var ids: Array[String] = []
		for choice: Dictionary in first.choices():
			assert_false(str(choice["id"]) in ids)
			ids.append(str(choice["id"]))
		assert_lte(first.choices().size(), 14)
	assert_lte(first.history.size(), 8)
	assert_lt(var_to_bytes(first.page()).size(), 12000)
	var page := first.page()
	(page["choices"] as Array).clear()
	assert_false(first.choices().is_empty(), "UI snapshots cannot mutate the server story")
	assert_eq(other.revision, 0)
	assert_eq(other.inventory.size(), 0)
	assert_false(other.won)
