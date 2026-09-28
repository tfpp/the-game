extends GutTest
## Pure gating logic for build_refresh (features/build_refresh/build_refresh.gd), kept
## free of scene/JavaScriptBridge access so it's unit-testable.

const BuildRefresh := preload("res://features/build_refresh/build_refresh.gd")


func test_no_refresh_when_build_matches() -> void:
	assert_false(BuildRefresh.should_refresh(""))


func test_refreshes_when_server_reports_a_different_build() -> void:
	assert_true(BuildRefresh.should_refresh("abc1234"))
