extends SceneTree
## Export repository metadata using the same collector as the native console.


func _initialize() -> void:
	var data: Dictionary = preload("res://features/console/git_snapshot.gd").collect()
	if data.is_empty():
		printerr("Repository snapshot unavailable.")
		quit(1)
		return
	var file := FileAccess.open("res://features/console/repo_snapshot.gd", FileAccess.WRITE)
	if file == null:
		printerr("Cannot write repository snapshot.")
		quit(1)
		return
	file.store_string("extends RefCounted\n\nconst DATA = " + JSON.stringify(data) + "\n")
	file.close()
	quit()
