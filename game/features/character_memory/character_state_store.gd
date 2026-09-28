class_name CharacterStateStore
extends RefCounted
## In-memory table of each account's last known position, plus JSON (de)serialization.
## Kept free of scene/file access so it's plain unit-testable, the same way
## `core/movement/source_movement.gd` keeps its math separate from the node that uses it.

var _positions: Dictionary = {}  # normalized account key -> Vector3


## Account display names are unique ignoring case, so trim and lowercase them into a key.
static func normalize_key(display_name: String) -> String:
	return display_name.strip_edges().to_lower()


func has_position(key: String) -> bool:
	return _positions.has(key)


func get_position(key: String) -> Vector3:
	return _positions.get(key, Vector3.ZERO)


func set_position(key: String, position: Vector3) -> void:
	_positions[key] = position


func to_json() -> String:
	var out := {}
	for key: String in _positions.keys():
		var pos: Vector3 = _positions[key]
		out[key] = {"x": pos.x, "y": pos.y, "z": pos.z}
	return JSON.stringify(out)


## Replaces all in-memory state from JSON text. Malformed or missing data is ignored,
## leaving whatever entries could be parsed (an empty store if none could).
func from_json(text: String) -> void:
	_positions.clear()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	for key: String in (parsed as Dictionary).keys():
		var entry: Variant = (parsed as Dictionary)[key]
		if entry is Dictionary and entry.has("x") and entry.has("y") and entry.has("z"):
			var pos := entry as Dictionary
			_positions[key] = Vector3(float(pos["x"]), float(pos["y"]), float(pos["z"]))
