class_name SlumArrivalPoint
extends Marker3D
## Registers a slum destination. ZoneInstances selects one for a private cab run;
## the developer elevator can also use its authored arrival directly. The garage
## registration belongs to procedural_rooms/Garage/Arrival on its top floor.

## Shown on the dev elevator's signage.
@export var slum_name: String = ""


func _ready() -> void:
	add_to_group(&"slum_arrival_points")
