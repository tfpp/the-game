extends RefCounted
## Join wall endpoints once, including inside corners and outside corridor turns.


static func apply(layout: Dictionary) -> void:
	var endpoints: Dictionary[Vector3, Array] = {}
	for wall: Dictionary in layout["walls"]:
		wall["join_a"] = 0.0
		wall["join_b"] = 0.0
		for end: String in ["a", "b"]:
			var point: Vector3 = wall[end].snapped(Vector3.ONE * 0.0001)
			if not endpoints.has(point):
				endpoints[point] = []
			endpoints[point].append({"wall": wall, "end": end})
	layout["corners"] = []
	for point: Vector3 in endpoints:
		var ends: Array = endpoints[point]
		if ends.size() != 2:
			continue
		var first: Dictionary = ends[0]["wall"]
		var second: Dictionary = ends[1]["wall"]
		if absf(first["normal"].dot(second["normal"])) > 0.01:
			continue
		# Hotel trim ends square at a service-room threshold; never mitre it into concrete.
		if (
			first.get("kit") != second.get("kit")
			and "concrete" in [first.get("kit"), second.get("kit")]
		):
			continue
		for index: int in 2:
			var wall: Dictionary = ends[index]["wall"]
			var neighbor: Dictionary = ends[1 - index]["wall"]
			var u: Vector3 = wall["b"] - wall["a"]
			u.y = 0
			wall["join_" + ends[index]["end"]] = neighbor["normal"].dot(u.normalized())
		var interior := float(first["join_" + ends[0]["end"]])
		if ends[0]["end"] == "b":
			interior = -interior
		layout["corners"].append(
			{
				"position": point,
				"kit":
				(
					"concrete"
					if "concrete" in [first.get("kit"), second.get("kit")]
					else first.get("kit", "classic")
				),
				"height": maxf(first["height"], second["height"]),
				"kind": "inside" if interior > 0 else "outside"
			}
		)
