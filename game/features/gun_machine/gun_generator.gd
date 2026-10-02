class_name GunGenerator
extends RefCounted
## Pure random-gun generation for the gun machine: picks an ammo type and rolls
## every other stat within that type's range. Deterministic given the
## RandomNumberGenerator it's handed, and free of scene access, so it's
## unit-testable the same way features/gnomes/gnome_math.gd keeps its math
## separate from the node that uses it.

enum AmmoType { BUCKSHOT, RIFLE, LOW_CALIBER, ROCKET, GRENADE, PLASMA, RAY }

## The ammo types an ordinary roll picks from. `RAY` is left out: it only ever comes
## as the Ray Gun, a fixed rare jackpot (`RAY_GUN_CHANCE`).
const REGULAR_AMMO_TYPES: Array[AmmoType] = [
	AmmoType.BUCKSHOT,
	AmmoType.RIFLE,
	AmmoType.LOW_CALIBER,
	AmmoType.ROCKET,
	AmmoType.GRENADE,
	AmmoType.PLASMA,
]

## Odds a purchase rolls the Ray Gun instead of a random gun. Call of Duty Zombies'
## mystery box gives it roughly a 1-in-30 chance on most maps, so this matches it.
const RAY_GUN_CHANCE := 1.0 / 30.0
const RAY_GUN_NAME := "Ray Gun"

const AMMO_NAMES := {
	AmmoType.BUCKSHOT: "Buckshot",
	AmmoType.RIFLE: "Rifle",
	AmmoType.LOW_CALIBER: "Low-caliber",
	AmmoType.ROCKET: "Rocket",
	AmmoType.GRENADE: "Grenade",
	AmmoType.PLASMA: "Plasma",
	AmmoType.RAY: "Ray",
}

const BARREL_NAMES := {1: "", 2: "Double-Barrel ", 3: "Triple-Barrel ", 4: "Quad-Barrel "}

## Ranges rolled per ammo type. `pellets`: mini-projectiles fired by each barrel per
## shot (a shotgun sprays several; everything else fires one). `gravity_scale`:
## fraction of world gravity the projectile falls under in flight (0 = flies dead
## straight, matching a laser or a fast rifle round more than physical reality).
## `bounces`: times a projectile that hits the world (not a player) bounces before
## it's removed, for grenades that skitter across the floor. `fuse_s`: seconds
## before an unexploded projectile detonates anyway (0 = only on impact).
## `explosion_radius`: 0 for a direct-hit-only projectile. `splash_force`: how far
## (in meters, at point-blank, falling off to 0 at `explosion_radius` the same way
## splash damage does) an explosion shoves everyone caught in it; 0 alongside a 0
## `explosion_radius`, since there's nothing to shove them with.
const AMMO_PROFILES := {
	AmmoType.BUCKSHOT:
	{
		"pellets": 8,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 0.0,
		"splash_force": 0.0,
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
		"splash_force": 0.0,
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
		"splash_force": 0.0,
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
		"splash_force": 5.0,
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
		"splash_force": 3.5,
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
		"splash_force": 0.0,
		"fire_rate": [3.0, 10.0],
		"damage": [8.0, 14.0],
		"magazine_size": [20, 50],
		"ammo_multiplier": [3, 6],
		"projectile_speed": [140.0, 170.0],
		"spread_degrees": [0.0, 1.0],
		"color": Color(0.3, 0.75, 0.95),
	},
	# Only the Ray Gun uses this, with fixed stats modeled on the Zombies original:
	# 20-round magazine, 160 rounds total, semi-auto green bolts that splash.
	AmmoType.RAY:
	{
		"pellets": 1,
		"gravity_scale": 0.0,
		"bounces": 0,
		"fuse_s": 0.0,
		"explosion_radius": 2.0,
		"splash_force": 1.5,
		"fire_rate": [3.0, 3.0],
		"damage": [60.0, 60.0],
		"magazine_size": [20, 20],
		"ammo_multiplier": [8, 8],
		"projectile_speed": [60.0, 60.0],
		"spread_degrees": [0.5, 0.5],
		"color": Color(0.3, 1.0, 0.25),
	},
}

const MIN_BARRELS := 1
const MAX_BARRELS := 4
## Weighting so extra barrels stay a rare treat, not the norm: index 0 is the
## chance of rolling exactly 1 barrel, index 1 of 2, and so on.
const BARREL_WEIGHTS := [0.55, 0.28, 0.12, 0.05]

## Odds a freshly rolled gun holds the trigger down (fires every tick of its
## `fire_rate` while `gun_fire` stays held) instead of needing a fresh press per
## shot. Independent of ammo type — a grenade launcher can go full-auto just as
## easily as a rifle, for better or worse.
const AUTOMATIC_CHANCE := 0.5


## The stat profile every gun of `ammo_type` shares, regardless of its rolled stats.
static func profile(ammo_type: AmmoType) -> Dictionary:
	return AMMO_PROFILES[ammo_type]


## One freshly rolled gun as a Dictionary (network-friendly: plain data, no Resource),
## keyed the same way for every ammo type so callers never branch on which fields
## exist. `rng` is injected so callers get deterministic, testable results.
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() < RAY_GUN_CHANCE:
		return ray_gun()
	var ammo_type: AmmoType = REGULAR_AMMO_TYPES[rng.randi_range(0, REGULAR_AMMO_TYPES.size() - 1)]
	return generate_selected(rng, ammo_type)


## Selected family keeps the same ranges as a kiosk roll. Zero barrels means random.
static func generate_selected(
	rng: RandomNumberGenerator, ammo_type: AmmoType, barrels: int = 0, automatic: int = -1
) -> Dictionary:
	if ammo_type == AmmoType.RAY:
		return ray_gun()
	var stats: Dictionary = AMMO_PROFILES[ammo_type]
	var magazine_size := rng.randi_range(
		maxi(int(stats["magazine_size"][0]), barrels), stats["magazine_size"][1]
	)
	# A gun can never fire if it has more barrels than rounds in a full magazine, so
	# barrel count is capped by whatever magazine size was just rolled.
	var barrel_count := barrels if barrels > 0 else mini(_roll_barrel_count(rng), magazine_size)
	var total_ammo := (
		magazine_size * rng.randi_range(stats["ammo_multiplier"][0], stats["ammo_multiplier"][1])
	)
	var is_automatic := rng.randf() < AUTOMATIC_CHANCE if automatic < 0 else automatic == 1
	return {
		"ammo_type": ammo_type,
		"barrel_count": barrel_count,
		"is_automatic": is_automatic,
		"fire_rate": rng.randf_range(stats["fire_rate"][0], stats["fire_rate"][1]),
		"magazine_size": magazine_size,
		"damage": rng.randf_range(stats["damage"][0], stats["damage"][1]),
		"total_ammo": total_ammo,
		"projectile_speed":
		rng.randf_range(stats["projectile_speed"][0], stats["projectile_speed"][1]),
		"spread_degrees": rng.randf_range(stats["spread_degrees"][0], stats["spread_degrees"][1]),
		"display_name": display_name(ammo_type, barrel_count, is_automatic),
	}


## The Ray Gun's fixed stats, in the same shape `generate` returns.
static func ray_gun() -> Dictionary:
	var stats: Dictionary = AMMO_PROFILES[AmmoType.RAY]
	var magazine_size: int = stats["magazine_size"][0]
	return {
		"ammo_type": AmmoType.RAY,
		"barrel_count": 1,
		"is_automatic": false,
		"fire_rate": stats["fire_rate"][0],
		"magazine_size": magazine_size,
		"damage": stats["damage"][0],
		"total_ammo": magazine_size * int(stats["ammo_multiplier"][0]),
		"projectile_speed": stats["projectile_speed"][0],
		"spread_degrees": stats["spread_degrees"][0],
		"display_name": RAY_GUN_NAME,
	}


static func is_ray_gun(stats: Dictionary) -> bool:
	return int(stats.get("ammo_type", -1)) == AmmoType.RAY


static func display_name(
	ammo_type: AmmoType, barrel_count: int, is_automatic: bool = false
) -> String:
	var barrels: String = BARREL_NAMES.get(barrel_count, "%d-Barrel " % barrel_count)
	var mode := "Auto " if is_automatic else ""
	return "%s%s%s Gun" % [barrels, mode, AMMO_NAMES[ammo_type]]


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
