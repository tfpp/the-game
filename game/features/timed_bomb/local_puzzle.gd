extends RefCounted
## Offline practice only. Dedicated servers never read this file.

var path := "user://timed_bomb_practice.json"
var data: Dictionary = {}


func load_or_create(now: int) -> bool:
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return false
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary:
			return false
		data = parsed
		return (
			valid_code(data.get("code"))
			and data.get("deadline") is float
			and str(data.get("state")) in ["armed", "defused", "exploded"]
		)
	var random := Crypto.new().generate_random_bytes(4).decode_u32(0)
	data = {"code": "%04d" % (random % 10000), "deadline": now + 86400, "state": "armed"}
	return save()


static func valid_code(value: Variant) -> bool:
	if not value is String or value.length() != 4:
		return false
	for index: int in 4:
		var digit: int = value.unicode_at(index)
		if digit < 48 or digit > 57:
			return false
	return true


func snapshot(now: int, guess := "") -> Dictionary:
	if data.is_empty():
		return {}
	var previous := data.duplicate()
	var message := "Enter the secret four-digit code."
	if data["state"] == "armed" and now >= int(data["deadline"]):
		data["state"] = "exploded"
	if guess != "" and data["state"] == "armed":
		if now < int(data.get("next_attempt", 0)):
			message = "Keypad cooling down. Try again shortly."
		else:
			data["next_attempt"] = now + 5
			message = "Incorrect code."
			if guess == data["code"]:
				data["state"] = "defused"
	if data != previous and not save():
		data = previous
		return {}
	if data["state"] == "defused":
		message = "Bomb defused."
	elif data["state"] == "exploded":
		message = "Bomb has gone off."
	return {
		"state": data["state"],
		"deadline": int(data["deadline"]),
		"remaining": maxi(0, int(data["deadline"]) - now),
		"message": message
	}


func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
