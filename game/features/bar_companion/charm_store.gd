class_name CharmStore
extends RefCounted
## Precise account snapshots. Call only from the authoritative BarCompanion.

var path := "user://bar_stats.json"
var records: Dictionary = {}
var _loaded := false


static func empty_row() -> Dictionary:
	return {"win": 0.0, "intox": 0.0, "luck": 0.0}


static func faded(row: Dictionary, seconds: float) -> Dictionary:
	return {
		"win": CharmMath.decay(float(row["win"]), seconds, CharmMath.WIN_FADE_S),
		"intox": CharmMath.decay(float(row["intox"]), seconds, CharmMath.SOBER_S),
		"luck": maxf(float(row["luck"]) - seconds, 0.0)
	}


func restore(account: int, now: float) -> Dictionary:
	_load()
	var saved: Dictionary = records.get(str(account), {})
	if saved.is_empty():
		return empty_row()
	return faded(saved, maxf(now - float(saved["at"]), 0.0))


func remember(account: int, row: Dictionary, now: float) -> void:
	_load()
	var saved := row.duplicate()
	saved["at"] = now
	records[str(account)] = saved


func save() -> void:
	if records.is_empty():
		return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("Cannot save bar stats")
		return
	file.store_string(JSON.stringify(records))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_warning("Cannot replace bar stats")


func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			decode(file.get_as_text())


func decode(text: String) -> void:
	_loaded = true
	records.clear()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return
	var parsed: Dictionary = parser.data
	for key: String in parsed:
		var row: Variant = parsed[key]
		if not key.is_valid_int() or int(key) <= 0 or not row is Dictionary:
			continue
		var valid := true
		for field: String in ["win", "intox", "luck", "at"]:
			var value: Variant = row.get(field)
			if not (value is float or value is int):
				valid = false
			elif not is_finite(float(value)) or float(value) < 0.0:
				valid = false
		if valid:
			records[key] = {
				"win": minf(float(row["win"]), CharmMath.MAX_WIN_CHARISMA),
				"intox": minf(float(row["intox"]), CharmMath.MAX_INTOXICATION),
				"luck": minf(float(row["luck"]), CharmMath.LUCK_S),
				"at": float(row["at"])
			}
