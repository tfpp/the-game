extends GutTest


func test_parse_headlines_reads_titles() -> void:
	var body := JSON.stringify(
		{"data": [{"title": " A \n"}, {"title": ""}, {"x": 1}, {"title": "B"}]}
	)
	assert_eq(NewsTicker.parse_headlines(body), PackedStringArray(["A", "B"]))


func test_parse_headlines_rejects_garbage() -> void:
	assert_true(NewsTicker.parse_headlines("nope").is_empty())
	assert_true(NewsTicker.parse_headlines('{"data": 3}').is_empty())


func test_ticker_text_falls_back_when_empty() -> void:
	assert_eq(NewsTicker.ticker_text(PackedStringArray()), NewsTicker.FALLBACK)
	assert_string_contains(NewsTicker.ticker_text(PackedStringArray(["A", "B"])), "A")


func test_feature_scrolls_ticker() -> void:
	var scene: Node = load("res://features/news_ticker/feature.tscn").instantiate()
	add_child_autofree(scene)
	var ticker := scene.get_node("Viewport/Ticker") as Label
	scene._process(0.1)
	var start := ticker.position.x
	scene._process(0.5)
	assert_lt(ticker.position.x, start)
	assert_eq(ticker.text.begins_with(NewsTicker.FALLBACK), true)


func test_only_dedicated_server_fetches() -> void:
	var saved: Network.Mode = Network.mode
	Network.mode = Network.Mode.OFFLINE
	assert_false(NewsTicker.is_news_server())
	Network.mode = Network.Mode.CLIENT
	assert_false(NewsTicker.is_news_server())
	Network.mode = Network.Mode.SERVER
	assert_true(NewsTicker.is_news_server())
	Network.mode = saved


func test_seconds_until_refresh_waits_fifteen_minutes() -> void:
	assert_eq(NewsTicker.REFRESH_SECONDS, 900.0)
	assert_eq(NewsTicker.seconds_until_refresh(1000.0, 1000.0), 900.0)
	assert_eq(NewsTicker.seconds_until_refresh(1000.0, 1600.0), 300.0)
	assert_eq(NewsTicker.seconds_until_refresh(1000.0, 5000.0), 0.0)
	assert_eq(NewsTicker.seconds_until_refresh(9000.0, 1000.0), 900.0)


func test_cache_round_trip_skips_fresh_fetch() -> void:
	var path := "user://test_news_cache.json"
	var writer := NewsTicker.new()
	writer.cache_path = path
	writer.headlines = PackedStringArray(["Cached A", "Cached B"])
	writer._save_cache()
	writer.free()
	var reader := NewsTicker.new()
	reader.cache_path = path
	reader._load_cache()
	assert_eq(reader.headlines, PackedStringArray(["Cached A", "Cached B"]))
	assert_gt(reader._next_fetch, 890.0)
	reader.free()
	DirAccess.remove_absolute(path)
