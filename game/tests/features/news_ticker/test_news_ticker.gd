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
