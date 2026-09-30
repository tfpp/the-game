class_name ProceduralSocketProfile
extends Resource
## Shared physical boundary used by module geometry and attachment validation.

@export var width := 3.0
@export var height := 3.0


func boundary() -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(-width * 0.5, 0, 0),
			Vector3(width * 0.5, 0, 0),
			Vector3(width * 0.5, height, 0),
			Vector3(-width * 0.5, height, 0)
		]
	)


func matches(other: ProceduralSocketProfile) -> bool:
	return is_equal_approx(width, other.width) and is_equal_approx(height, other.height)
