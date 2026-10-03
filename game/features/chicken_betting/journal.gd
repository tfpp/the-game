class_name ChickenBetJournal
extends RefCounted
## Authenticated debit intents survive a server restart. No balances or secrets.
## Unfinished matches recover as refunds; completed matches keep their fixed payout.

var path := "user://chicken-bets.cfg"
var entries: Dictionary = {}


func load_entries() -> void:
	var file := ConfigFile.new()
	if file.load(path) == OK:
		entries = file.get_value("book", "entries", {})


func store(id: String, ticket: Dictionary) -> bool:
	var previous := entries.duplicate(true)
	entries[id] = ticket.duplicate(true)
	if _save():
		return true
	entries = previous
	return false


func erase(id: String) -> void:
	entries.erase(id)
	_save()


func _save() -> bool:
	var file := ConfigFile.new()
	file.set_value("book", "entries", entries)
	# Rename a complete file rather than overwrite the only recovery record.
	if file.save(path + ".tmp") != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
