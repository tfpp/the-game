extends RefCounted
## Visible stair treads/risers. The shell supplies continuous walkable collision.

const Geometry := preload("res://features/world_builder/geometry.gd")


static func build(g: Geometry, flight: Dictionary) -> void:
	var axis: Vector2 = flight["axis"]
	var start: Vector2 = flight["start"]
	var low: float = flight["low"]
	var high: float = flight["high"]
	var length: float = flight["length"]
	if high < low:
		start += axis * length
		axis = -axis
		var swap := low
		low = high
		high = swap
	var forward := Vector3(axis.x, 0, axis.y)
	var across := Vector3(-axis.y, 0, axis.x) * float(flight["width"]) / 2
	var origin := Vector3(start.x, low, start.y)
	var steps: int = flight["steps"]
	var tread := length / steps
	var riser := (high - low) / steps
	for index: int in steps:
		var a := origin + forward * index * tread + Vector3.UP * index * riser
		var b := a + Vector3.UP * riser
		var c := b + forward * tread
		g.quad("wood", [a - across, a + across, b + across, b - across], -forward, false)
		g.quad("floor", [b - across, b + across, c + across, c - across], Vector3.UP, false)
		var lip := b + Vector3.UP * 0.002
		g.quad(
			"gold",
			[
				lip - across,
				lip + across,
				lip + across + forward * 0.035,
				lip - across + forward * 0.035
			],
			Vector3.UP,
			false
		)
