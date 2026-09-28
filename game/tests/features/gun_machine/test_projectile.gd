extends GutTest
## Coverage for the cosmetic muzzle-to-trajectory ease `projectile.gd` uses so a shot
## fired straight down the shooter's own view axis is still visible instead of
## popping in already on-axis with the camera (see `Projectile._visual_offset`).

const ProjectileScene := preload("res://features/gun_machine/projectile.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")

var _rig: GunRig


func before_each() -> void:
	_rig = GunRigScene.instantiate() as GunRig
	_rig.peer_id = 1
	add_child_autofree(_rig)
	_rig.set_process(false)
	_rig.equip(GunGenerator.generate(RandomNumberGenerator.new()))
	_rig._rebuild_view()
	_rig.global_position = Vector3(1, 2, 3)


func _spawn(at: Vector3) -> Projectile:
	var projectile := ProjectileScene.instantiate() as Projectile
	projectile.shooter_peer = 1
	projectile.net_position = at
	add_child_autofree(projectile)
	projectile.set_physics_process(false)
	return projectile


func test_visual_starts_at_the_shooters_muzzle_and_eases_onto_the_real_trajectory() -> void:
	var origin := Vector3(10, 2, 10)
	var projectile := _spawn(origin)
	assert_eq(projectile.position, origin, "the real, authoritative position never moves")
	var expected_start := _rig.muzzle_position() - origin
	assert_true((projectile._visual_offset as Vector3).is_equal_approx(expected_start))
	await wait_seconds(Projectile.MUZZLE_VISUAL_EASE_S + 0.05)
	assert_true((projectile._visual.position as Vector3).is_equal_approx(Vector3.ZERO))
	assert_eq(projectile.position, origin, "easing the visual never touches the real position")


func test_no_matching_rig_leaves_the_visual_unoffset() -> void:
	var lonely := ProjectileScene.instantiate() as Projectile
	lonely.shooter_peer = 99
	lonely.net_position = Vector3(4, 5, 6)
	add_child_autofree(lonely)
	lonely.set_physics_process(false)
	assert_eq(lonely._visual.position, Vector3.ZERO)
