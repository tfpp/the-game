class_name ScummArcadeProgressStore
extends RefCounted
## Durable replay checkpoint. Never accepts saves uploaded by multiplayer clients.

const MAX_BYTES := 4194304
const MAGIC := "SCUMM01\n"

var path: String
var failure := ""


func _init(save_path: String) -> void:
	path = save_path


# gdlint: disable=max-returns
func save_progress(session: ScummArcadeSession, runtime: String) -> bool:
	failure = ""
	var payload := var_to_bytes(
		{"version": 1, "runtime": runtime, "tick": session.tick, "history": session.history}
	)
	if payload.size() > MAX_BYTES:
		return _failed("Arcade save is too large")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return _failed("Cannot create arcade save directory")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _failed("Cannot write arcade progress")
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_buffer(_digest(payload))
	file.store_buffer(payload)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return _failed("Cannot flush arcade progress")
	# Replace only after a complete write. Retain the last complete checkpoint.
	if FileAccess.file_exists(path) and _read(path, runtime) != null:
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			return _failed("Cannot back up arcade progress")
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return _failed("Cannot install arcade progress")
	return true


func load_progress(runtime: String) -> ScummArcadeSession:
	failure = ""
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var restored := _read(candidate, runtime)
		if restored != null:
			failure = ""
			return restored
		failure = "Saved arcade progress is damaged or belongs to another runtime"
	return null


func _read(candidate: String, runtime: String) -> ScummArcadeSession:
	var file := FileAccess.open(candidate, FileAccess.READ)
	if file == null or file.get_length() < 40 or file.get_length() > MAX_BYTES + 40:
		return null
	if file.get_buffer(8).get_string_from_utf8() != MAGIC:
		return null
	var digest := file.get_buffer(32)
	var payload := file.get_buffer(file.get_length() - 40)
	if digest != _digest(payload):
		return null
	var data: Variant = bytes_to_var(payload)
	if not data is Dictionary or data.get("version") != 1 or data.get("runtime") != runtime:
		return null
	return ScummArcadeSession.restore(data)


func _failed(message: String) -> bool:
	failure = message
	return false


static func _digest(payload: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	return hash.finish()
