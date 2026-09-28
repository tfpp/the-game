class_name ScummArcadeSession
extends RefCounted
## Sparse, bounded replay log. Each committed tick is immutable and lasts 20 ms.

const TICK_SECONDS := 0.02
const MAX_TICKS := 180000  # One hour, then a player can start a fresh session.
const MAX_EVENTS := 32768
const MAX_PER_TICK := 12
const BATCH_TICKS := 250
const ALLOWED_KEYS := [13, 27, 46]

var tick := 0
var event_count := 0
var history: Dictionary = {}
var pending: Array = []


static func valid_event(event: Array) -> bool:
	if event.size() != 4:
		return false
	for value: Variant in event:
		if not value is int:
			return false
	return (
		event[0] >= 0
		and event[0] <= 6
		and event[1] >= 0
		and event[1] < 320
		and event[2] >= 0
		and event[2] < 200
		and (event[3] == 0 if event[0] < 5 else event[3] in ALLOWED_KEYS)
	)


func enqueue(event: Array) -> bool:
	if not valid_event(event) or finished():
		return false
	if pending.size() >= MAX_PER_TICK or event_count + pending.size() >= MAX_EVENTS:
		return false
	# Coalesce motion, but never discard button transitions.
	if event[0] == 0 and not pending.is_empty() and pending.back()[0] == 0:
		pending[pending.size() - 1] = event.duplicate()
	else:
		pending.append(event.duplicate())
	return true


func advance() -> void:
	if finished():
		return
	if not pending.is_empty():
		history[tick] = pending.duplicate(true)
		event_count += pending.size()
	pending.clear()
	tick += 1


func finished() -> bool:
	return tick >= MAX_TICKS or event_count >= MAX_EVENTS


func batch(from_tick: int) -> Array:
	var result: Array = []
	if from_tick < 0 or from_tick > tick:
		return result
	for index: int in range(from_tick, mini(tick, from_tick + BATCH_TICKS)):
		result.append(history.get(index, []).duplicate(true))
	return result


func release_buttons() -> void:
	# Reserve room by dropping unsimulated inputs when the operator leaves.
	pending.clear()
	pending.append([2, 160, 100, 0])
	pending.append([4, 160, 100, 0])
	for key: int in ALLOWED_KEYS:
		pending.append([6, 160, 100, key])
	pending.resize(mini(pending.size(), MAX_EVENTS - event_count))


static func restore(data: Dictionary) -> ScummArcadeSession:
	var saved_tick: Variant = data.get("tick")
	var saved_history: Variant = data.get("history")
	if not saved_tick is int or saved_tick < 0 or saved_tick > MAX_TICKS:
		return null
	if not saved_history is Dictionary or saved_history.size() > MAX_EVENTS:
		return null
	var restored := ScummArcadeSession.new()
	for index: Variant in saved_history:
		if not index is int or index < 0 or index >= saved_tick:
			return null
		var events: Variant = saved_history[index]
		if not events is Array or events.is_empty() or events.size() > MAX_PER_TICK:
			return null
		for event: Variant in events:
			if not event is Array or not valid_event(event):
				return null
		restored.event_count += events.size()
		if restored.event_count > MAX_EVENTS:
			return null
	restored.tick = saved_tick
	restored.history = saved_history.duplicate(true)
	# An operator's connection and held inputs never survive a restore.
	restored.release_buttons()
	return restored
