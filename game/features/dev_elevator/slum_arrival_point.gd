class_name SlumArrivalPoint
extends Marker3D
## Tags a Marker3D as a place a player can land when sent to a slum map. Today the only
## reader is dev_elevator.gd (a debug-only shortcut for testing); eventually the Golden
## Crown elevator will roll a random member of the `slum_arrival_points` group instead of
## always going to the same place. At that point every slum feature registers by adding
## this script to one Marker3D, the same way features/parking_garage/feature.tscn's
## `Garage/GarageArrival` already does — no changes needed here or in
## slum_destinations.gd.

## Shown on the dev elevator's signage.
@export var slum_name: String = ""


func _ready() -> void:
	add_to_group(&"slum_arrival_points")
