extends SceneTree
## Build explicit UV geometry before painting the sign's own 64px atlas.

const FONT: Dictionary[String, Array] = {
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
}
var _surface := SurfaceTool.new()
var _guide := Image.create(256, 256, false, Image.FORMAT_RGB8)


func _initialize() -> void:
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(Vector3.ZERO, Vector3(5.8, 1.6, .24), 0)
	for y: float in [-.76, .76]:
		_box(Vector3(0, y, .16), Vector3(5.8, .08, .12), 1)
	for x: float in [-2.86, 2.86]:
		_box(Vector3(x, 0, .16), Vector3(.08, 1.6, .12), 1)
	_text("GOLDEN CROWN", .065, .25)
	_text("CASINO", .072, -.38)
	var mesh := _surface.commit()
	DirAccess.make_dir_recursive_absolute("res://assets/street_district/models")
	assert(ResourceSaver.save(mesh, "res://assets/street_district/models/casino_marquee.res") == OK)
	var colors: Array[Color] = [Color("19312e"), Color("bd9239"), Color("e8d8b0"), Color("622b29")]
	for y: int in range(256):
		for x: int in range(256):
			_guide.set_pixel(x, y, colors[(1 if x >= 128 else 0) + (2 if y >= 128 else 0)])
	var guide_path := ProjectSettings.globalize_path(
		"res://../docs/design/model-sources/casino-marquee/uv-guide.png"
	)
	assert(_guide.save_png(guide_path) == OK)
	print("CASINO_SIGN_MODEL_UV_READY: ", mesh.get_faces().size() / 3, " triangles")
	quit()


func _text(value: String, pixel: float, y: float) -> void:
	var width := (value.length() * 6 - 1) * pixel
	for i: int in value.length():
		if value[i] == " ":
			continue
		var rows: Array = FONT[value[i]]
		for row: int in rows.size():
			var col := 0
			while col < 5:
				if rows[row][col] == "0":
					col += 1
					continue
				var start := col
				while col < 5 and rows[row][col] == "1":
					col += 1
				_box(
					Vector3(
						-width / 2 + (i * 6 + (start + col) * .5) * pixel,
						y + (3 - row) * pixel,
						.185
					),
					Vector3((col - start) * pixel, pixel, .09),
					1
				)


func _box(center: Vector3, size: Vector3, region: int) -> void:
	var h := size / 2
	var points: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z),
		Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z),
		Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z),
		Vector3(-h.x, h.y, h.z),
	]
	for face: Array in [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]
	]:
		var normal := -(
			(points[face[1]] - points[face[0]])
			. cross(points[face[2]] - points[face[0]])
			. normalized()
		)
		var uv: Array[Vector2] = [
			Vector2(.04, .04), Vector2(.46, .04), Vector2(.46, .46), Vector2(.04, .46)
		]
		for index: int in [0, 1, 2, 0, 2, 3]:
			_surface.set_normal(normal)
			_surface.set_uv(uv[index] + Vector2(.5 if region % 2 else 0, .5 if region >= 2 else 0))
			_surface.add_vertex(center + points[face[index]])
