class_name Gnome
extends StaticBody3D
## One gnome of a burrow (gnome_train.gd). The train owns every gnome's state; this
## body only gives weapon hitscans something to hit (physics layer 2, like frogs, so it
## never blocks player movement) and routes hits back to the train. A dead or
## burrowed gnome is only hidden, never freed, so bringing it back costs nothing.

var train: Node
var index := 0
var _shown := true

@onready var body: Node3D = $Body
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	add_to_group(&"killable")
	add_to_group(&"gnomes")


## Shows the model and enables the hitbox while the gnome is out of its hole and alive.
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	body.visible = shown
	_collider.disabled = not shown


func is_shown() -> bool:
	return _shown


## Called by the server's weapon hitscans (see features/holdables/hand.gd).
func take_hit(_attacker_peer: int) -> void:
	if train != null:
		train.call(&"kill_gnome", index)
