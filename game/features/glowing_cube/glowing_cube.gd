extends Node3D
## A small glowing cube that idles in the middle of the room, slowly spinning in place.
## Purely decorative: the rotation is deterministic and runs locally on every peer, so it
## needs no server authority or MultiplayerSynchronizer.

const ROTATION_SPEED := 0.4  # radians per second


func _process(delta: float) -> void:
	rotation.y = next_rotation(rotation.y, delta)


## Pure step, kept free of scene access so the wrap-around math is unit-testable.
static func next_rotation(current_y: float, delta: float) -> float:
	return wrapf(current_y + ROTATION_SPEED * delta, 0.0, TAU)
