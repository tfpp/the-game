class_name ScummArcadeInbox
extends RefCounted
## Bounded, ordered authoritative input queue. Worker completion never stalls delivery.

const MAX_FRAMES := 500
var next_tick := 0
var frames: Array = []


func append(from_tick: int, incoming: Array) -> bool:
	var skip := maxi(0, next_tick - from_tick)
	if skip >= incoming.size():
		return true
	if from_tick + skip != next_tick or frames.size() + incoming.size() - skip > MAX_FRAMES:
		return false
	for index: int in range(skip, incoming.size()):
		frames.append(incoming[index])
	next_tick += incoming.size() - skip
	return true


func take(tick: int) -> Array:
	var count := mini(frames.size(), 250 - tick % 250)
	var batch := frames.slice(0, count)
	frames = frames.slice(count)
	return batch
