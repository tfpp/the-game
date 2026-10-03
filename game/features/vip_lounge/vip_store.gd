class_name VipStore
extends RefCounted
## Server-local account records, matching the existing bar stats persistence.
## Transaction intents are flushed before requesting idempotent wallet settlement.

var path := "user://vip_lounge.json"
var records: Dictionary = {}
var loaded := false


func load_records() -> void:
	if loaded:
		return
	loaded = true
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return
	var parsed: Dictionary = parser.data
	for key: String in parsed:
		if not key.is_valid_int() or int(key) <= 0 or not parsed[key] is Dictionary:
			continue
		var row: Dictionary = parsed[key]
		if valid_record(row):
			records[key] = row


static func valid_record(row: Dictionary) -> bool:
	var defaults := VipRules.empty_record()
	for field: String in defaults:
		if not row.has(field):
			return false
		var value: Variant = row[field]
		if defaults[field] is bool and not value is bool:
			return false
		if defaults[field] is int:
			if not (value is int or value is float):
				return false
			if not is_finite(float(value)) or float(value) < 0.0:
				return false
		if defaults[field] is Array and not value is Array:
			return false
	if not row["transaction"] is Dictionary:
		return false
	for field: String in ["hosts", "collection", "wardrobe"]:
		for item: Variant in row[field]:
			if not item is String:
				return false
	var tx: Dictionary = row["transaction"]
	if not tx.is_empty():
		if tx.get("kind") not in ["gift", "play", "mission"]:
			return false
		if not tx.get("id") is String or str(tx["id"]).length() != 64:
			return false
		for field: String in ["wager", "payout", "at"]:
			var value: Variant = tx.get(field)
			if not (value is float or value is int):
				return false
			if not is_finite(float(value)) or float(value) < 0.0:
				return false
		if tx.get("kind") == "play" and int(tx["wager"]) not in VipRules.WAGERS:
			return false
		if not tx.get("reels") is Array or not tx.get("collectible") is String:
			return false
	return true


func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(records))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
