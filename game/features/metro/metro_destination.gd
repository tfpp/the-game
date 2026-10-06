extends GpsDestination


func available() -> bool:
	var access := get_parent() as MetroAccess
	return super.available() and access != null and access.discovered(multiplayer.get_unique_id())
