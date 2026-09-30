extends SceneTree
## Original weathered garage textures for the live basement; no external artwork.
## godot --headless --path game -s res://features/procedural_rooms/tools/build_garage_textures.gd

const ASSET_DIR := "res://assets/procedural_rooms/garage_textures"
const MATERIAL_DIR := "res://features/procedural_rooms/materials"
const SIZE := 128
const TILE_METRES := 2.56
## id, base colour, two-sided
const TILES := [
	["floor", "4a4d4f", false],
	["wall", "5b5c59", true],
	["ceiling", "3b3d3e", false],
	["rail", "8a7a2e", true]
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIR))
	for tile: Array in TILES:
		var image := _paint(tile[0], Color(tile[1]))
		var error := image.save_png("%s/garage_%s.png" % [ASSET_DIR, tile[0]])
		if error != OK:
			push_error("Cannot save texture " + str(tile[0]))
			quit(1)
			return
		_save_material(tile[0], tile[2])
	quit()


static func _noise(seed_value: int, frequency: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 3
	return noise.get_seamless_image(SIZE, SIZE)


## Seamless noise image, remapped to -1..1 by sampling it.
static func _tiled(noise: Image, x: int, y: int) -> float:
	return noise.get_pixel(x, y).r * 2.0 - 1.0


static func _paint(id: String, base: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var grain := _noise(id.hash(), 0.35)
	var stains := _noise(id.hash() + 1, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	for y: int in SIZE:
		for x: int in SIZE:
			var shade := 1.0 + _tiled(grain, x, y) * 0.16 + (rng.randf() - 0.5) * 0.07
			var stain := _tiled(stains, x, y)
			var color := base * shade
			match id:
				"floor":
					# Oil and water stains pool into dark blotches.
					if stain > 0.3:
						color = color.darkened(clampf((stain - 0.3) * 1.6, 0, 0.35))
					if y % 64 < 1 or x % 64 < 1:
						color = color.darkened(0.3)  # Saw-cut expansion joints.
				"wall":
					# Board-form seams and rust/water streaks below the ceiling.
					if y % 32 == 0:
						color = color.darkened(0.25)
					var streak := sin(x * 0.9 + stain * 6.0) * 0.5 + 0.5
					if streak > 0.86:
						color = color.lerp(
							Color("4a3b2c"), (streak - 0.86) * 3.5 * (1.0 - y / 180.0)
						)
					if y > 104:
						color = color.darkened(0.2 + (y - 104) / 120.0)  # Grime line.
				"ceiling":
					color = color.darkened(clampf(stain * 0.8, 0, 0.4))  # Soot.
					if x % 42 < 2:
						color = color.darkened(0.35)  # Formwork beams.
				"rail":
					# Chipped hazard paint over rusted steel.
					var band := (x + y) % 32 < 16
					color = (Color("b39a2a") if band else Color("262625")) * shade
					if stain > 0.2:
						color = Color("5d3a22") * shade
			image.set_pixel(x, y, color.clamp())
	# Cracks wander across the concrete surfaces.
	if id != "rail":
		for crack: int in 3:
			var point := Vector2(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
			var heading := rng.randf() * TAU
			for step: int in rng.randi_range(20, 45):
				heading += rng.randf_range(-0.6, 0.6)
				point += Vector2.from_angle(heading)
				var px := posmod(int(point.x), SIZE)
				var py := posmod(int(point.y), SIZE)
				image.set_pixel(px, py, image.get_pixel(px, py).darkened(0.45))
	return image


func _save_material(id: String, two_sided: bool) -> void:
	var scale := 1.0 / TILE_METRES
	var text := '[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
	text += '[ext_resource type="Texture2D" path="%s/garage_%s.png" id="1"]\n\n' % [ASSET_DIR, id]
	text += '[resource]\nresource_name = "Garage %s"\n' % id
	if two_sided:
		text += "cull_mode = 2\n"
	text += 'albedo_texture = ExtResource("1")\nroughness = 1.0\nmetallic_specular = 0.2\n'
	text += (
		"texture_filter = %d\ntexture_repeat = true\n"
		% BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	)
	text += "uv1_scale = Vector3(%f, %f, %f)\n" % [scale, scale, scale]
	text += "uv1_triplanar = true\nuv1_world_triplanar = true\nuv1_triplanar_sharpness = 16.0\n"
	var file := FileAccess.open("%s/garage_%s.tres" % [MATERIAL_DIR, id], FileAccess.WRITE)
	if file == null:
		push_error("Cannot save material " + id)
		quit(1)
		return
	file.store_string(text)
