class_name SecurityRules
extends RefCounted
## Pure rules for Golden Crown security: which offences count, where the guards
## work, their timings, and the poses of a carried and thrown troublemaker.
## No scene access, so tests can check every rule directly.

## Guard behaviour, replicated as `CasinoGuard.net_state`.
enum GuardState { POSTED, RESPONDING, LIFTING, CARRYING, DOORS, THROWING, RETURNING }
## A detained player's phase, replicated in `CasinoSecurity.detentions`.
enum Phase { NONE, HELD, CARRIED, THROWN, LANDED }

## The main hall the guards patrol, in world space (the feature root sits at the
## origin): the promenade and the gaming pit, below the mariachi balcony.
const HALL := AABB(Vector3(-23.6, -1.7, -19.6), Vector3(47.2, 4.7, 39.2))

## Offence id -> what security calls it. Every offence is server-detected.
const OFFENCES := {
	&"firearm": "Brandishing a firearm",
	&"assault": "Assaulting a guest",
	&"security": "Picking a fight with security",
	&"vandalism": "Spray-painting the Golden Crown",
}
## What the guard who answers says to the offender, by offence.
const CALLOUTS := {
	&"firearm": "No guns in the Golden Crown. Don't. Move.",
	&"assault": "We don't hit the customers here, pal.",
	&"security": "Did you just punch me? Cute.",
	&"vandalism": "That wallpaper is older than you. Freeze.",
}
const LIFT_LINE := "Up you go."
const THROW_LINE := "Enjoy the metro."
const SPEAKER := "Security"

## Guard pace in m/s: a buff jog to the scene, a heavy walk with a passenger, a
## stroll back to the post.
const RESPOND_SPEED := 4.2
const CARRY_SPEED := 2.4
const RETURN_SPEED := 1.6
## How close (horizontally, metres) a guard gets before scooping someone up, and
## how far below their feet the guard's floor may be (someone on a table). Guards
## walk to within APPROACH when the floor allows, else as close as it lets them.
const GRAB_RANGE := 1.5
const APPROACH := 0.75
const GRAB_DROP := 1.6
## Phase lengths in seconds.
const LIFT_S := 1.0
const DOOR_WAIT_S := 2.5
const THROW_S := 0.9
## Seconds into the throw when the guard lets go.
const RELEASE_S := 0.45
const FLIGHT_S := 0.6
const LANDED_S := 5.0
## A guard that cannot reach an offender within this long lets them go.
const RESPOND_TIMEOUT_S := 25.0
## An offence waiting for a free guard expires after this long.
const QUEUE_TIMEOUT_S := 20.0
## Give up on the metro after this long and put the player down at the doors.
const DELIVERY_TIMEOUT_S := 30.0

## Guard build: overall scale (they are big) and the shoulder the carry rides on,
## in guard space (guard faces -Z, feet at the origin).
const GUARD_SCALE := 1.12
const CARRY_SHOULDER := Vector3(0.26, 1.66, 0.04)
## Head-down droop of a carried body behind the guard's back, radians.
const CARRY_DROOP := 0.22
## Where a thrown body flies to inside the metro cab, from the threshold marker
## (+Z faces the room): 1.4 m deep, waist height.
const CAB_TARGET := Vector3(0, 1.0, -1.4)
## Where the guard stands to throw, from the threshold marker.
const THROW_STAND := Vector3(0, 0, 1.9)
const FLIGHT_ARC := 0.7


static func is_offence(offence: StringName) -> bool:
	return OFFENCES.has(offence)


static func offence_name(offence: StringName) -> String:
	return str(OFFENCES.get(offence, "Causing trouble"))


static func callout(offence: StringName) -> String:
	return str(CALLOUTS.get(offence, "Freeze."))


## True when a point (a player's capsule centre) is somewhere guards patrol.
static func in_jurisdiction(point: Vector3) -> bool:
	return HALL.has_point(point)


## Yaw that points a -Z-facing model along `direction`.
static func facing_yaw(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## True when a guard at `guard` stands close enough to lift someone whose capsule
## bottom (feet) is at `feet`.
static func can_grab(guard: Vector3, feet: Vector3) -> bool:
	var flat := Vector2(feet.x - guard.x, feet.z - guard.z).length()
	var rise := feet.y - guard.y
	return flat <= GRAB_RANGE and rise > -0.5 and rise <= GRAB_DROP


## Index of the guard to send: the nearest free one (`free[i]`) by straight-line
## distance, or -1 when every guard is busy.
static func pick_guard(positions: Array[Vector3], free: Array[bool], target: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for index: int in positions.size():
		if not free[index]:
			continue
		var distance := positions[index].distance_to(target)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


## World transform of a carried body (Player/Body, centred on the capsule) slung
## belly-down over a guard's right shoulder: legs in front, head hanging down the
## guard's back.
static func carry_body(guard: Transform3D) -> Transform3D:
	# Body +Y (head) toward the guard's back (+Z); body front (-Z) faces down.
	var slung := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	return guard * Transform3D(Basis(Vector3.RIGHT, CARRY_DROOP) * slung, CARRY_SHOULDER)


## The body `lift` (0..1) of the way from where it stood (`start`, world) up onto
## the guard's shoulder.
static func lifted_body(start: Transform3D, guard: Transform3D, lift: float) -> Transform3D:
	var t := smoothstep(0.0, 1.0, clampf(lift, 0.0, 1.0))
	var slung := carry_body(guard)
	var basis := start.basis.orthonormalized().slerp(slung.basis.orthonormalized(), t)
	var at := start.origin.lerp(slung.origin, t) + Vector3.UP * 0.35 * sin(t * PI)
	return Transform3D(basis, at)


## Where the carried player's capsule centre is pinned: the slung body's centre.
static func carry_point(guard: Transform3D) -> Vector3:
	return carry_body(guard).origin


## World eye of a carried player looking around from their dangling head.
static func carried_eye(body: Transform3D, height_scale: float = 1.0) -> Vector3:
	return body * (Vector3(0, 0.62, -0.08) * height_scale)


## The thrown body `t` seconds into its flight from `from` to `to`: an arc that
## tumbles head over heels once. Past FLIGHT_S it stays at `to`.
static func flight_body(from: Transform3D, to: Vector3, t: float) -> Transform3D:
	var k := clampf(t / FLIGHT_S, 0.0, 1.0)
	var at := from.origin.lerp(to, k) + Vector3.UP * FLIGHT_ARC * 4.0 * k * (1.0 - k)
	var tumble := Basis(from.basis.x.normalized(), -TAU * 0.5 * k)
	return Transform3D(tumble * from.basis, at)


## Local screen darkness (0 clear .. 1 black) for the detainee.
static func darkness(phase: int, elapsed: float) -> float:
	match phase:
		Phase.THROWN:
			return smoothstep(FLIGHT_S * 0.4, FLIGHT_S, elapsed)
		Phase.LANDED:
			return 1.0 - smoothstep(0.2, 1.4, elapsed)
	return 0.0


## The detainee's on-screen caption.
static func caption(phase: int, offence: StringName) -> String:
	match phase:
		Phase.HELD:
			return "SECURITY! Stay where you are.\n%s" % offence_name(offence)
		Phase.CARRIED:
			return "You're being escorted out.\n%s" % offence_name(offence)
		Phase.THROWN:
			return "Golden Crown security threw you into the metro."
		Phase.LANDED:
			return "Thrown out for: %s\nTake a metro elevator back up." % offence_name(offence)
	return ""


## Guard rig pose blend weights for a state `elapsed` seconds in:
## {arms: 0 at sides .. 1 crossed, carry: 0..1 shoulder carry, throw: 0..1 heave}.
static func guard_pose(state: int, elapsed: float) -> Dictionary:
	var arms := 0.0
	var carry := 0.0
	var heave := 0.0
	match state:
		GuardState.POSTED:
			arms = smoothstep(0.0, 0.8, elapsed)
		GuardState.LIFTING:
			carry = smoothstep(0.0, LIFT_S, elapsed)
		GuardState.CARRYING, GuardState.DOORS:
			carry = 1.0
		GuardState.THROWING:
			carry = 1.0 if elapsed < RELEASE_S else 1.0 - smoothstep(RELEASE_S, THROW_S, elapsed)
			heave = sin(clampf(elapsed / THROW_S, 0.0, 1.0) * PI)
	return {"arms": arms, "carry": carry, "throw": heave}


## Pace for a guard state, metres per second (0 when standing still).
static func speed_for(state: int) -> float:
	match state:
		GuardState.RESPONDING:
			return RESPOND_SPEED
		GuardState.CARRYING:
			return CARRY_SPEED
		GuardState.RETURNING:
			return RETURN_SPEED
	return 0.0
