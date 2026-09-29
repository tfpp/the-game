class_name GarageEnemyTiers
extends RefCounted
## Pure data and rules for the parking garage's hostiles, kept separate from the
## node so the tuning and the targeting math are unit-testable on their own.
##
## Players arrive on P1 (ground) and climb, so danger grows with distance from
## the employee entrance: P1 holds lone lurkers, P2 adds gunmen and P3 (the
## darkest floor) adds fast stalkers. Tougher tiers mainly move faster, hit
## harder and attack from range instead of simply soaking more hits.

enum Tier { LURKER, GUNMAN, STALKER }

## How far above or below an enemy's feet a player still counts as on its floor.
## Floors are 3.3m apart and a player's origin sits ~0.9m above their feet.
const SAME_FLOOR_BAND := 1.8
## Moving players are harder to hit; this speed (m/s) gives the minimum chance.
const DODGE_SPEED := 10.0
const MIN_HIT_CHANCE := 0.3

const PROFILES := {
	Tier.LURKER:
	{
		"name": "Lurker",
		"hits": 1,
		"speed": 3.2,
		"damage": 10.0,
		"range": 1.6,
		"cooldown": 1.1,
		"windup": 0.35,
		"ranged": false,
		"aggro": 10.0,
		"leash": 12.0,
		"scale": 0.85,
		"skin": Color(0.36, 0.33, 0.28),
		"eyes": Color(1.0, 0.75, 0.2),
		"respawn": 25.0,
	},
	Tier.GUNMAN:
	{
		"name": "Gunman",
		"hits": 2,
		"speed": 3.8,
		"damage": 12.0,
		"range": 14.0,
		"cooldown": 1.8,
		"windup": 0.6,
		"ranged": true,
		"aggro": 16.0,
		"leash": 14.0,
		"scale": 1.0,
		"skin": Color(0.22, 0.27, 0.3),
		"eyes": Color(0.3, 0.9, 1.0),
		"respawn": 30.0,
	},
	Tier.STALKER:
	{
		"name": "Stalker",
		"hits": 3,
		"speed": 6.2,
		"damage": 20.0,
		"range": 1.8,
		"cooldown": 0.8,
		"windup": 0.25,
		"ranged": false,
		"aggro": 18.0,
		"leash": 18.0,
		"scale": 1.15,
		"skin": Color(0.3, 0.12, 0.12),
		"eyes": Color(1.0, 0.15, 0.1),
		"respawn": 35.0,
	},
}


static func profile(tier: int) -> Dictionary:
	return PROFILES.get(tier, PROFILES[Tier.LURKER])


## True when `player_origin` (a Player's capsule center) stands on the floor whose
## surface is at `feet.y`.
static func same_floor(feet: Vector3, player_origin: Vector3) -> bool:
	return absf(player_origin.y - 0.9 - feet.y) <= SAME_FLOOR_BAND


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
