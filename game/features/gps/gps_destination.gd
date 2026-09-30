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

## Existing scene markers stay Places unless explicitly categorized.
@export_enum("Places", "People", "Animals", "Objects") var category := "Places"
var tracks_source := false
var source: Node3D


func _enter_tree() -> void:
	add_to_group(GROUP)


func available() -> bool:
	if not tracks_source:
		return is_inside_tree()
	if not is_instance_valid(source) or not source.is_inside_tree():
		return false
	if source is ItemPickup:
		return not (source as ItemPickup).net_taken
	if source is CoinPickup:
		return (source as CoinPickup).available
	if source is Gnome:
		return (source as Gnome).is_shown()
	var alive: Variant = source.get("net_alive")
	return alive == null or bool(alive)


func destination_position() -> Vector3:
	return source.global_position if tracks_source and available() else global_position
