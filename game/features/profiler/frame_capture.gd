extends RefCounted
## Bounded wall-clock intervals and measured landmarks, not sampled script stacks.

const GRAPH_LIMIT := 240
const MISS_LIMIT := 120
const EVENT_LIMIT := 128

var enabled := false
var budget_ms := 1000.0 / 60.0
var frames: Array[Dictionary] = []
var misses: Array[Dictionary] = []
var total_misses := 0
var _start_us := -1
var _frame_id := 0
var _events: Array[Dictionary] = []
var _dropped := 0


func reset() -> void:
	frames.clear()
	misses.clear()
	total_misses = 0
	_start_us = -1
	_events.clear()
	_dropped = 0


func boundary(now_us: int, frame_id: int) -> void:
	if not enabled:
		return
	if _start_us >= 0 and now_us > _start_us:
		var duration := float(now_us - _start_us) / 1000.0
		var frame := {
			"id": _frame_id,
			"duration_ms": duration,
			"budget_ms": budget_ms,
			"events": _events.duplicate(true),
			"dropped": _dropped,
		}
		frames.append(frame)
		if frames.size() > GRAPH_LIMIT:
			frames.pop_front()
		if duration > budget_ms:
			misses.append(frame)
			total_misses += 1
			if misses.size() > MISS_LIMIT:
				misses.pop_front()
	_start_us = now_us
	_frame_id = frame_id
	_events = [{"name": "Process frame boundary", "offset_ms": 0.0}]
	_dropped = 0


func mark(name: String, now_us: int) -> void:
	if not enabled or _start_us < 0 or now_us < _start_us:
		return
	if _events.size() >= EVENT_LIMIT:
		_dropped += 1
		return
	_events.append({"name": name, "offset_ms": float(now_us - _start_us) / 1000.0})


func restart_interval() -> void:
	_start_us = -1
	_events.clear()
	_dropped = 0


static func trace_text(frame: Dictionary) -> String:
	var lines: PackedStringArray = [
		(
			"Frame #%d: %.3f ms / %.3f ms budget"
			% [frame["id"], frame["duration_ms"], frame["budget_ms"]]
		),
		"Wall-clock landmarks (gaps include engine work, waiting and pacing).",
		"Not script call stacks or CPU/GPU attribution."
	]
	var previous := 0.0
	for event: Dictionary in frame["events"]:
		var offset := float(event["offset_ms"])
		lines.append("%8.3f ms  (+%.3f)  %s" % [offset, offset - previous, event["name"]])
		previous = offset
	lines.append(
		(
			"%8.3f ms  (+%.3f)  Next process frame boundary"
			% [frame["duration_ms"], float(frame["duration_ms"]) - previous]
		)
	)
	if int(frame["dropped"]) > 0:
		lines.append("%d extra landmarks omitted (capture limit)." % frame["dropped"])
	return "\n".join(lines)
