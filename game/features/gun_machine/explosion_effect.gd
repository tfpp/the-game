class_name GunExplosionEffect
extends RefCounted
## Cosmetic burst for an exploding projectile (any ammo type with a nonzero
## `explosion_radius` — currently rockets and grenades): a bright flash plus a
## growing, fading shockwave sphere sized to the blast radius, and the shared
## "explosion" sound cue (features/game_audio). Purely cosmetic and unnetworked,
## like features/animal_effects/mesh_explosion.gd's death burst — every peer spawns
## and animates its own copy from projectile.gd's `_play_explosion` event.

const FLASH_DURATION_S := 0.25
const SHOCKWAVE_DURATION_S := 0.4
const SHOCKWAVE_START_RADIUS := 0.2


## Spawns the effect as a child of `parent` at `at`, sized off the ammo type's
## `explosion_radius`. Self-removing once its tweens finish.
static func spawn(parent: Node, at: Vector3, radius: float) -> void:
	var effect := Node3D.new()
	effect.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(effect)
	effect.global_position = at
	GameAudio.play_at(parent, &"explosion", at)
	_spawn_flash(effect, radius)
	_spawn_shockwave(effect, radius)
	var cleanup := effect.create_tween()
	cleanup.tween_interval(maxf(FLASH_DURATION_S, SHOCKWAVE_DURATION_S))
	cleanup.tween_callback(effect.queue_free)


static func _spawn_flash(effect: Node3D, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 6.0
	light.omni_range = maxf(radius * 1.5, 2.0)
	effect.add_child(light)
	var tween := effect.create_tween()
	tween.tween_property(light, "light_energy", 0.0, FLASH_DURATION_S)
	tween.tween_callback(light.queue_free)


static func _spawn_shockwave(effect: Node3D, radius: float) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = SHOCKWAVE_START_RADIUS
	mesh.height = SHOCKWAVE_START_RADIUS * 2.0
	sphere.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.6, 0.15, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.set_surface_override_material(0, material)
	effect.add_child(sphere)
	var target_scale := Vector3.ONE * maxf(radius / SHOCKWAVE_START_RADIUS, 1.0)
	var tween := effect.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(sphere, "scale", target_scale, SHOCKWAVE_DURATION_S)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(material, "albedo_color:a", 0.0, SHOCKWAVE_DURATION_S)
	tween.chain().tween_callback(sphere.queue_free)
