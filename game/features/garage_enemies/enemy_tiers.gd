class_name GarageEnemyTiers
extends RefCounted
## Pure data and rules for the parking garages' hostiles, kept separate from the
## node so the tuning and the targeting math are unit-testable on their own.
##
## Every tier wears the player avatar rig (`enemy_model.gd`). From weakest to
## strongest: ragged brawlers (LURKER) shamble up and punch, knifers (STALKER)
## sprint in with a blade, and gunmen (GUNMAN) shoot from range. The enum keeps
## its original order so existing scenes keep their tiers; use `STRENGTH` to rank.

enum Tier { LURKER, GUNMAN, STALKER }

## Weakest to strongest.
const STRENGTH: Array[int] = [Tier.LURKER, Tier.STALKER, Tier.GUNMAN]

## How far above or below an enemy's feet a player still counts as on its floor.
## Floors are 3.3m apart and a player's origin sits ~0.9m above their feet.
const SAME_FLOOR_BAND := 1.8
## Moving players are harder to hit; this speed (m/s) gives the minimum chance.
const DODGE_SPEED := 10.0
const MIN_HIT_CHANCE := 0.3

const PROFILES := {
	Tier.LURKER:
	{
		"name": "Ragged brawler",
		"weapon": "fists",
		"hits": 1,
		"speed": 2.6,
		"damage": 8.0,
		"range": 1.5,
		"cooldown": 1.2,
		"windup": 0.4,
		"ranged": false,
		"aggro": 10.0,
		"leash": 12.0,
		"scale": 1.0,
		"respawn": 25.0,
	},
	Tier.STALKER:
	{
		"name": "Knifer",
		"weapon": "knife",
		"hits": 2,
		"speed": 6.4,
		"damage": 18.0,
		"range": 1.7,
		"cooldown": 0.8,
		"windup": 0.25,
		"ranged": false,
		"aggro": 16.0,
		"leash": 18.0,
		"scale": 1.0,
		"respawn": 30.0,
	},
	Tier.GUNMAN:
	{
		"name": "Gunman",
		"weapon": "gun",
		"hits": 3,
		"speed": 3.8,
		"damage": 15.0,
		"range": 16.0,
		"cooldown": 1.6,
		"windup": 0.6,
		"ranged": true,
		"aggro": 18.0,
		"leash": 18.0,
		"scale": 1.0,
		"respawn": 35.0,
	},
}


static func profile(tier: int) -> Dictionary:
	return PROFILES.get(tier, PROFILES[Tier.LURKER])


## True when `player_origin` (a Player's capsule center) stands on the floor whose
## surface is at `feet.y`.
static func same_floor(feet: Vector3, player_origin: Vector3) -> bool:
	return absf(player_origin.y - 0.9 - feet.y) <= SAME_FLOOR_BAND


## How far away an enemy with this aggro radius notices a player. Crouching halves
## it, so sneaking players get closer, but enemies can still see them.
static func notice_radius(aggro: float, crouching: bool) -> float:
	return aggro * (Crouch.NOTICE_SCALE if crouching else 1.0)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Index of the nearest candidate inside `radius` on the same floor, or -1.
static func nearest(feet: Vector3, candidates: Array[Vector3], radius: float) -> int:
	var best := -1
	var best_distance := radius
	for index: int in candidates.size():
		var point := candidates[index]
		if not same_floor(feet, point):
			continue
		var distance := flat_distance(feet, point)
		if distance <= best_distance:
			best = index
			best_distance = distance
	return best


## Yaw that turns a model facing -Z towards `direction`.
static func facing_yaw(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Chance a gunman's shot lands on a target moving at `speed` m/s.
static func hit_chance(speed: float) -> float:
	return clampf(1.0 - speed / DODGE_SPEED, MIN_HIT_CHANCE, 0.9)


## Gunmen keep their distance rather than rushing in; melee tiers close in.
static func wants_to_advance(tier: int, distance: float) -> bool:
	var info := profile(tier)
	if info["ranged"]:
		return distance > float(info["range"]) * 0.5
	return distance > float(info["range"]) * 0.8


## 0 for the weakest tier, rising with strength.
static func rank(tier: int) -> int:
	return STRENGTH.find(tier)
