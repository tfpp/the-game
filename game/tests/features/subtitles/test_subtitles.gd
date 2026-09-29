extends GutTest

const SUBTITLES := preload("res://features/subtitles/feature.tscn")
var _subs: Subtitles


func before_each() -> void:
	_subs = SUBTITLES.instantiate()
	add_child_autofree(_subs)


func test_say_shows_speaker_and_line_bottom_centre() -> void:
	Subtitles.say(get_tree(), "Donald Trump", "Paid $100.")
	assert_true(_subs.is_showing())
	assert_eq(_subs.current_text(), "Donald Trump: Paid $100.")
	await wait_frames(2)
	var panel := _subs.get_node("Control/Panel") as Control
	var screen := _subs.get_viewport().get_visible_rect().size
	var centre := panel.position.x + panel.size.x * 0.5
	assert_almost_eq(centre, screen.x * 0.5, 1.0)
	assert_gt(panel.position.y, screen.y * 0.6, "sits in the lower part of the screen")


func test_line_fades_after_its_duration() -> void:
	_subs.show_line("A", "Hi")
	_subs._process(Subtitles.duration_for("Hi") + 0.1)
	assert_false(_subs.is_showing())


func test_new_line_replaces_old() -> void:
	_subs.show_line("A", "first")
	_subs.show_line("B", "second")
	assert_eq(_subs.current_text(), "B: second")


func test_duration_scales_and_caps() -> void:
	assert_gt(Subtitles.duration_for("a longer line"), Subtitles.duration_for("hi"))
	assert_eq(Subtitles.duration_for("x".repeat(1000)), Subtitles.MAX_S)


func test_bbcode_in_text_is_escaped() -> void:
	_subs.show_line("", "[b]hi[/b]")
	assert_eq(_subs.current_text(), "[b]hi[/b]")
