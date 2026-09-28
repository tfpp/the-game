class_name GunGenerator
extends RefCounted
## Pure random-gun generation for the gun machine: picks an ammo type and rolls
## every other stat within that type's range. Deterministic given the
## RandomNumberGenerator it's handed, and free of scene access, so it's
## unit-testable the same way features/gnomes/gnome_math.gd keeps its math
## separate from the node that uses it.

enum AmmoType { BUCKSHOT, RIFLE, LOW_CALIBER, ROCKET, GRENADE, PLASMA }

const AMMO_NAMES := {
	AmmoType.BUCKSHOT: "Buckshot",
	AmmoType.RIFLE: "Rifle",
	AmmoType.LOW_CALIBER: "Low-caliber",
	AmmoType.ROCKET: "Rocket",
	AmmoType.GRENADE: "Grenade",
	AmmoType.PLASMA: "Plasma",
}

const BARREL_NAMES := {1: "", 2: "Double-Barrel ", 3: "Triple-Barrel ", 4: "Quad-Barrel "}

## Ranges rolled per ammo type. `pellets`: mini-projectiles fired by each barrel per
## shot (a shotgun sprays several; everything else fires one). `gravity_scale`:
## fraction of world gravity the projectile falls under in flight (0 = flies dead
## straight, matching a laser or a fast rifle round more than physical reality).
## `bounces`: times a projectile that hits the world (not a player) bounces before
## it's removed, for grenades that skitter across the floor. `fuse_s`: seconds
## before an unexploded projectile detonates anyway (0 = only on impact).
## `explosion_radius`: 0 for a direct-hit-only projectile.
const AMMO_PROFILES := {
	AmmoType.BUCKSHOT:
	{
		"pellets": 8,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 0.0,
		"fire_rate": [0.7, 1.4],
		"damage": [4.0, 7.0],
		"magazine_size": [4, 8],
		"ammo_multiplier": [4, 8],
		"projectile_speed": [55.0, 70.0],
		"spread_degrees": [6.0, 12.0],
		"color": Color(0.85, 0.65, 0.25),
	},
	AmmoType.RIFLE:
	{
		"pellets": 1,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 0.0,
		"fire_rate": [4.0, 9.0],
		"damage": [10.0, 18.0],
		"magazine_size": [15, 30],
		"ammo_multiplier": [3, 6],
		"projectile_speed": [110.0, 150.0],
		"spread_degrees": [0.5, 2.5],
		"color": Color(0.55, 0.55, 0.6),
	},
	AmmoType.LOW_CALIBER:
	{
		"pellets": 1,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 0.0,
		"fire_rate": [3.0, 7.0],
		"damage": [5.0, 9.0],
		"magazine_size": [8, 17],
		"ammo_multiplier": [3, 7],
		"projectile_speed": [80.0, 110.0],
		"spread_degrees": [1.5, 4.5],
		"color": Color(0.7, 0.72, 0.68),
	},
	AmmoType.ROCKET:
	{
		"pellets": 1,
		"gravity_scale": 0.1,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 4.0,
		"fire_rate": [0.3, 0.8],
		"damage": [55.0, 90.0],
		"magazine_size": [1, 2],
		"ammo_multiplier": [3, 5],
		"projectile_speed": [25.0, 38.0],
		"spread_degrees": [0.0, 1.0],
		"color": Color(0.5, 0.15, 0.1),
	},
	AmmoType.GRENADE:
	{
		"pellets": 1,
		"gravity_scale": 1.0,
		"bounces": 3,
		"fuse_s": 2.2,
		"explosion_radius": 3.5,
		"fire_rate": [0.5, 1.0],
		"damage": [35.0, 65.0],
		"magazine_size": [1, 4],
		"ammo_multiplier": [3, 4],
		"projectile_speed": [14.0, 24.0],
		"spread_degrees": [0.0, 2.0],
		"color": Color(0.25, 0.4, 0.2),
	},
	AmmoType.PLASMA:
	{
		"pellets": 1,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 0.0,
		"fire_rate": [3.0, 10.0],
		"damage": [8.0, 14.0],
		"magazine_size": [20, 50],
		"ammo_multiplier": [3, 6],
		"projectile_speed": [140.0, 170.0],
		"spread_degrees": [0.0, 1.0],
		"color": Color(0.3, 0.75, 0.95),
	},
}

const MIN_BARRELS := 1
const MAX_BARRELS := 4
## Weighting so extra barrels stay a rare treat, not the norm: index 0 is the
## chance of rolling exactly 1 barrel, index 1 of 2, and so on.
const BARREL_WEIGHTS := [0.55, 0.28, 0.12, 0.05]


## The stat profile every gun of `ammo_type` shares, regardless of its rolled stats.
static func profile(ammo_type: AmmoType) -> Dictionary:
	return AMMO_PROFILES[ammo_type]


## One freshly rolled gun as a Dictionary (network-friendly: plain data, no Resource),
## keyed the same way for every ammo type so callers never branch on which fields
## exist. `rng` is injected so callers get deterministic, testable results.
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var ammo_type: AmmoType = rng.randi_range(0, AMMO_NAMES.size() - 1)
	var stats: Dictionary = AMMO_PROFILES[ammo_type]
	var magazine_size := rng.randi_range(stats["magazine_size"][0], stats["magazine_size"][1])
	# A gun can never fire if it has more barrels than rounds in a full magazine, so
	# barrel count is capped by whatever magazine size was just rolled.
	var barrel_count := mini(_roll_barrel_count(rng), magazine_size)
	var total_ammo := (
		magazine_size * rng.randi_range(stats["ammo_multiplier"][0], stats["ammo_multiplier"][1])
	)
	return {
		"ammo_type": ammo_type,
		"barrel_count": barrel_count,
		"fire_rate": rng.randf_range(stats["fire_rate"][0], stats["fire_rate"][1]),
		"magazine_size": magazine_size,
		"damage": rng.randf_range(stats["damage"][0], stats["damage"][1]),
		"total_ammo": total_ammo,
		"projectile_speed":
		rng.randf_range(stats["projectile_speed"][0], stats["projectile_speed"][1]),
		"spread_degrees": rng.randf_range(stats["spread_degrees"][0], stats["spread_degrees"][1]),
		"display_name": display_name(ammo_type, barrel_count),
	}


static func display_name(ammo_type: AmmoType, barrel_count: int) -> String:
	var barrels: String = BARREL_NAMES.get(barrel_count, "%d-Barrel " % barrel_count)
	return "%s%s Gun" % [barrels, AMMO_NAMES[ammo_type]]


static func ammo_name(ammo_type: AmmoType) -> String:
	return AMMO_NAMES[ammo_type]


static func _roll_barrel_count(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for index: int in BARREL_WEIGHTS.size():
		cumulative += BARREL_WEIGHTS[index]
		if roll <= cumulative:
			return MIN_BARRELS + index
	return MAX_BARRELS
