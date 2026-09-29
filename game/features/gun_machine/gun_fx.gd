class_name GunFx
extends RefCounted
## Shared, cached visuals for guns and projectiles, so buying or firing a gun never
## builds new materials, meshes or lights mid-game. On the web (Compatibility
## renderer) every new light and material variant compiles a shader the first time
## it's drawn, which showed up as hitches when buying and firing. Flashes are
## unshaded glow meshes instead of `OmniLight3D`s, materials are shared per color, and
## `warm_up()` draws every variant once at load so their shaders are ready.

const FLASH_MESH_RADIUS := 0.5

static var _materials: Dictionary = {}
static var _flash_mesh: SphereMesh


## A shared opaque material of `color`, optionally emissive. Callers mustn't edit it.
static func material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(), emissive]
	if _materials.has(key):
		return _materials[key]
	var made := StandardMaterial3D.new()
	made.albedo_color = color
	if emissive:
		made.emission_enabled = true
		made.emission = color
		made.emission_energy_multiplier = 1.5
	_materials[key] = made
	return made


## A shared unshaded, additive material for flashes. Fading effects duplicate it:
## a duplicate reuses the same compiled shader.
static func glow_material(color: Color) -> StandardMaterial3D:
	var key := "%s|glow" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var made := StandardMaterial3D.new()
	made.albedo_color = color
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	made.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	made.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = made
	return made


## A shared unshaded, alpha-blended material (the explosion shockwave's variant).
static func fade_material(color: Color) -> StandardMaterial3D:
	var key := "%s|fade" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var made := StandardMaterial3D.new()
	made.albedo_color = color
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = made
	return made


## The unit sphere every flash scales, shared so no mesh is generated per shot.
static func flash_mesh() -> SphereMesh:
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = FLASH_MESH_RADIUS
		_flash_mesh.height = FLASH_MESH_RADIUS * 2.0
		_flash_mesh.radial_segments = 12
		_flash_mesh.rings = 6
	return _flash_mesh


## A glow ball of `diameter` metres: a cheap stand-in for a flash light.
static func flash(color: Color, diameter: float) -> MeshInstance3D:
	var ball := MeshInstance3D.new()
	ball.mesh = flash_mesh()
	ball.material_override = glow_material(color)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * diameter / (FLASH_MESH_RADIUS * 2.0)
	return ball


## Every material variant guns and projectiles draw, for `warm_up()` and tests.
static func warm_up_materials() -> Array[StandardMaterial3D]:
	var list: Array[StandardMaterial3D] = [
		material(GunView.BODY_COLOR),
		material(Color.WHITE, true),
		glow_material(Color.WHITE),
		fade_material(Color.WHITE),
	]
	return list


## Client: puts one tiny sphere per material variant just in front of `camera` so
## the renderer compiles their shaders now, then frees them after a few frames.
static func warm_up(camera: Camera3D) -> void:
	var holder := Node3D.new()
	holder.name = "GunFxWarmUp"
	camera.add_child(holder)
	holder.position = Vector3(0, 0, -0.5)
	for index: int in warm_up_materials().size():
		var ball := MeshInstance3D.new()
		ball.mesh = flash_mesh()
		ball.material_override = warm_up_materials()[index]
		ball.scale = Vector3.ONE * 0.002
		ball.position = Vector3(index * 0.002, 0, 0)
		holder.add_child(ball)
	for _frame: int in 3:
		await camera.get_tree().process_frame
	if is_instance_valid(holder):
		holder.queue_free()
