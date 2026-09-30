extends Node3D
## Spawns the casino patrons on the server through a MultiplayerSpawner, the
## same pattern features/shooting_gallery/shooting_gallery.gd uses. Spawn data
## carries each patron's index, so every peer builds the same look and route.

const TRUMP_SCENE := preload("res://features/casino_patrons/trump.tscn")
const MITCH_SCENE := preload("res://features/casino_patrons/mitch.tscn")

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
		_spawner.spawn({"index": PatronModel.TRUMP_LOOK})
		_spawner.spawn({"index": PatronModel.MITCH_LOOK})


## Runs on every peer (spawn_function).
func _spawn_patron(data: Variant) -> Node:
	var index := int((data as Dictionary)["index"])
	var scene := PATRON_SCENE
	if index == PatronModel.TRUMP_LOOK:
		scene = TRUMP_SCENE
	elif index == PatronModel.MITCH_LOOK:
		scene = MITCH_SCENE
	var patron := scene.instantiate() as CasinoPatron
	patron.name = "Patron%d" % index
	patron.look = index
	patron.route = PatronMath.route(
		PatronModel.MAMDANI_LOOK if index == PatronModel.TRUMP_LOOK else index
	)
	patron.position = patron.route[0]
	if index == PatronModel.TRUMP_LOOK:
		patron.position += Vector3(0, 0, -0.7)
		patron.route = [patron.position]
	elif index == PatronModel.MITCH_LOOK:
		patron.route.assign(PatronMath.MITCH_ROUTE)
		patron.position = patron.route[0]
	patron.net_position = patron.position
	return patron
