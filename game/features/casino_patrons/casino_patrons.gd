extends Node3D
## Spawns the casino patrons on the server through a MultiplayerSpawner, the
## same pattern features/shooting_gallery/shooting_gallery.gd uses. Spawn data
## carries each patron's index, so every peer builds the same look and route.

const PATRON_SCENE := preload("res://features/casino_patrons/patron.tscn")

@onready var _patrons: Node3D = $Patrons
@onready var _spawner: MultiplayerSpawner = $Spawner


func _ready() -> void:
	_spawner.spawn_function = _spawn_patron
	Network.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(_mode: Network.Mode) -> void:
	for child: Node in _patrons.get_children():
		_patrons.remove_child(child)
		child.queue_free()
	if Network.is_authoritative():
		for index: int in PatronMath.ROUTES.size():
			_spawner.spawn({"index": index})


## Runs on every peer (spawn_function).
func _spawn_patron(data: Variant) -> Node:
	var index := int((data as Dictionary)["index"])
	var patron := PATRON_SCENE.instantiate() as CasinoPatron
	patron.name = "Patron%d" % index
	patron.look = index
	patron.route = PatronMath.route(index)
	patron.position = patron.route[0]
	patron.net_position = patron.position
	return patron
