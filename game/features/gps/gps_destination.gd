class_name GpsDestination
extends Marker3D
## A place players can pick in the GPS phone. Add one for every new room or area.
## The marker sits on the floor where the route should end.

const GROUP := &"gps_destinations"

## Name shown in the phone's list, e.g. "Wine Cellar".
@export var label := ""
## Short description shown under the name.
@export var hint := ""
## Optional global extent of an area that isn't a `StreamedRoom` but is only
## reachable through doors (e.g. the parking garage). Empty means none.
@export var area := AABB()


func _enter_tree() -> void:
	add_to_group(GROUP)
