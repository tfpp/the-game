extends Node
## Compare discovery CPU work on the same loaded world, without rendering/FPS claims.

const SAMPLES := 50


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := $Game
	game.get_node("Features/character_memory").queue_free()
	await get_tree().create_timer(1.0).timeout
	var radar: Control = game.get_node("Features/radar/Map")
	radar.set_process(false)
	radar._center = Vector2.ZERO
	radar._height = 0.94
	var indexed: Array[Node3D] = []
	var recursive: Array[Node3D] = []
	# Exclude the one-time index build and engine mesh-cache warmup from both measurements.
	radar._collect(game, indexed)
	_legacy_collect(game, recursive, radar)
	if indexed.size() != recursive.size():
		_fail("Nearby geometry count changed")
		return
	for source: Node3D in recursive:
		if not indexed.has(source):
			_fail("Nearby geometry membership changed")
			return
	var old_times: Array[int] = []
	var new_times: Array[int] = []
	for sample: int in SAMPLES:
		recursive.clear()
		var start := Time.get_ticks_usec()
		_legacy_collect(game, recursive, radar)
		old_times.append(Time.get_ticks_usec() - start)
		indexed.clear()
		start = Time.get_ticks_usec()
		radar._collect(game, indexed)
		new_times.append(Time.get_ticks_usec() - start)
	old_times.sort()
	new_times.sort()
	print(
		"RADAR_SCAN_PROBE PASS nodes=",
		game.find_children("*", "", true, false).size(),
		" candidates=",
		radar._sources.size(),
		" nearby=",
		indexed.size(),
		" recursive_median_us=",
		old_times[SAMPLES / 2],
		" indexed_median_us=",
		new_times[SAMPLES / 2],
		" recursive_p95_us=",
		old_times[47],
		" indexed_p95_us=",
		new_times[47]
	)
	get_tree().quit()


func _legacy_collect(node: Node, result: Array[Node3D], radar: Control) -> void:
	# Reference the old traversal, sharing the unchanged bounds/range filter.
	if node is CSGShape3D:
		radar._append_source(node, result)
		return
	if node is CollisionShape3D and node.is_in_group(&"radar_geometry"):
		var collider := node as CollisionShape3D
		if (
			not collider.disabled
			and (collider.shape is BoxShape3D or collider.shape is ConcavePolygonShape3D)
		):
			radar._append_source(node, result)
			return
	for child: Node in node.get_children():
		_legacy_collect(child, result, radar)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
