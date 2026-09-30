class_name GarageEnemyModel
extends PatronModel
## A garage hostile on the shared player avatar rig (`PatronModel` from
## features/casino_patrons, itself `BlockPlayerModel`). Each tier dresses and arms
## it differently: ragged brawlers wear torn, patched clothes and punch, knifers
## wear dark hoodies with a bandana and hold a blade, gunmen wear tactical gear
## with a balaclava and a pistol. Faces -Z with its feet at the origin. Cosmetic
## only: every peer builds and poses its own copy from replicated state.

## How long a punch, slash or shot's follow-through pose lasts.
const STRIKE_S := 0.3
const HURT_S := 0.25
## Hand targets in model space (feet at the origin, facing -Z), reached with the
## rig's own arm IK (`SkinnedHuman.reach_grip`).
const GUARD_RIGHT := Vector3(0.14, 1.45, -0.28)
const GUARD_LEFT := Vector3(-0.14, 1.4, -0.26)
const JAB := Vector3(0.08, 1.42, -0.66)
const LOW_GRIP := Vector3(0.26, 0.95, -0.22)
const KNIFE_RAISED := Vector3(0.28, 1.9, 0.02)
const KNIFE_SLASH := Vector3(0.02, 1.0, -0.55)
const AIM := Vector3(0.1, 1.38, -0.62)
const AIM_SUPPORT := Vector3(0.0, 1.32, -0.5)

## Dressing per tier; enemies pick a variant from their name so a floor doesn't
## look like clones. Colors index ClothingCatalog.COLORS (-1 bare skin), hair
## PlayerAppearance styles and colors, skin PlayerSkin tones.
const VARIANTS := {
	GarageEnemyTiers.Tier.LURKER:
	[
		{"skin": 2, "hair": "long", "hair_color": 3, "shirt": 9, "pants": 10, "tie": -1},
		{"skin": 5, "hair": "bald", "hair_color": 0, "shirt": 6, "pants": 9, "tie": -1},
		{"skin": 1, "hair": "crop", "hair_color": 4, "shirt": 10, "pants": 1, "tie": -1},
		{"skin": 7, "hair": "classic", "hair_color": 0, "shirt": -1, "pants": 9, "tie": -1},
	],
	GarageEnemyTiers.Tier.STALKER:
	[
		{"skin": 3, "hair": "crop", "hair_color": 0, "shirt": 1, "pants": 1, "tie": -1},
		{"skin": 0, "hair": "swept", "hair_color": 1, "shirt": 1, "pants": 10, "tie": -1},
		{"skin": 6, "hair": "crop", "hair_color": 0, "shirt": 11, "pants": 1, "tie": -1},
	],
	GarageEnemyTiers.Tier.GUNMAN:
	[
		{"skin": 4, "hair": "bald", "hair_color": 0, "shirt": -1, "pants": -1, "tie": -1},
		{"skin": 1, "hair": "bald", "hair_color": 0, "shirt": -1, "pants": -1, "tie": -1},
	],
}

var weapon := "fists"
## The held knife or pistol, repositioned onto the right hand every pose.
var held: Node3D

var _strike := 0.0
var _hurt := 0.0


static func variant(tier: int, index: int) -> Dictionary:
	var list: Array = VARIANTS.get(tier, VARIANTS[GarageEnemyTiers.Tier.LURKER])
	return list[posmod(index, list.size())]


## Dresses and arms the rig for `tier`; `index` picks the outfit variant.
func equip(tier: int, index: int) -> void:
	var look := variant(tier, index)
	weapon = str(GarageEnemyTiers.profile(tier)["weapon"])
	dress_up(look)
	match weapon:
		"knife":
			_hoodie(look)
			held = _knife()
		"gun":
			var gear := {
				"skin": look["skin"], "hair": look["hair"], "hair_color": look["hair_color"]
			}
			gear["eyes"] = 0
			gear["outfit"] = "tactical"
			avatar.set_appearance(gear)
			_tactical()
			held = _pistol()
		_:
			_rags(look, index)
	if held != null:
		add_child(held)


## `speed` is the enemy's ground speed (m/s); knifers break into the rig's run.
## `raised` is the replicated wind-up: fists come up, the knife goes overhead, the
## pistol aims. `aiming` keeps a gunman's arm up while it has a target.
func animate(delta: float, speed: float, raised: bool, aiming: bool = false) -> void:
	if avatar == null:
		return
	_strike = maxf(_strike - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	avatar.seated = false
	avatar.animate(delta, Vector3(0, 0, -speed), true, RIG_MAX_SPEED)
	if _hurt > 0.0:
		avatar._torso.rotation.x += 0.35 * _hurt / HURT_S
		avatar._head.rotation.x = 0.4 * _hurt / HURT_S
		avatar.human.pose(avatar, false, false)
	var striking := _strike > 0.0
	match weapon:
		"knife":
			var grip := KNIFE_SLASH if striking else (KNIFE_RAISED if raised else LOW_GRIP)
			_reach(true, grip)
		"gun":
			if raised or aiming or striking:
				_reach(true, AIM)
				_reach(false, AIM_SUPPORT)
		_:
			if raised or striking:
				_reach(true, JAB if striking else GUARD_RIGHT)
				_reach(false, GUARD_LEFT)
	_place_held()


## Plays the punch, slash or shot follow-through.
func strike() -> void:
	_strike = STRIKE_S


## Recoils from a hit.
func flash() -> void:
	_hurt = HURT_S


func _reach(right: bool, target: Vector3) -> void:
	avatar.human.reach_grip(right, to_global(target))


## Keeps the weapon in the right hand, pointing along the forearm.
func _place_held() -> void:
	if held == null:
		return
	var hand := to_local(hand_position(true))
	var elbow := to_local(bone_position("ForearmR"))
	var along := hand - elbow
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	held.position = hand
	held.basis = Basis.looking_at(
		along.normalized(), Vector3.UP if absf(along.normalized().y) < 0.95 else Vector3.BACK
	)


## Torn hems, mismatched patches and a grubby face for the brawlers.
func _rags(look: Dictionary, index: int) -> void:
	var shirt := int(look["shirt"])
	var cloth := (
		ClothingCatalog.COLORS[shirt] if shirt >= 0 else ClothingCatalog.COLORS[int(look["pants"])]
	)
	var torn := _material(cloth.darkened(0.35))
	for strip: int in 4:
		var x := -0.13 + strip * 0.085
		var length := 0.08 + float((strip + index) % 3) * 0.05
		var rag := _part(
			"Rag%d" % strip,
			torso_items,
			Vector3(x, 0.02 - length * 0.5, CHEST_Z + 0.01),
			Vector3(0.05, length, 0.012),
			torn
		)
		rag.rotation.z = 0.25 * (1.0 if strip % 2 == 0 else -1.0)
	var patch := _material(ClothingCatalog.COLORS[(index * 5 + 4) % ClothingCatalog.COLORS.size()])
	_part(
		"Patch", torso_items, Vector3(0.08, 0.36, CHEST_Z - 0.004), Vector3(0.08, 0.07, 0.01), patch
	)
	var grime := _material(Color(0.2, 0.16, 0.12))
	_part(
		"Grime", head_items, Vector3(-0.04, 0.14, FACE_Z - 0.002), Vector3(0.06, 0.04, 0.008), grime
	)
	if index % 2 == 0:
		var beanie := _material(cloth.darkened(0.2))
		_part("Beanie", head_items, Vector3(0, 0.33, 0.0), Vector3(0.2, 0.08, 0.2), beanie)


## A red bandana over the mouth and a hood hanging behind the head.
func _hoodie(look: Dictionary) -> void:
	var hood := _material(ClothingCatalog.COLORS[int(look["shirt"])].darkened(0.1))
	_part("Hood", head_items, Vector3(0, 0.24, 0.05), Vector3(0.22, 0.22, 0.14), hood)
	var bandana := _material(Color(0.55, 0.08, 0.08))
	_part(
		"Bandana", head_items, Vector3(0, 0.13, FACE_Z - 0.006), Vector3(0.17, 0.08, 0.015), bandana
	)


## A plate carrier and a black balaclava.
func _tactical() -> void:
	var black := _material(Color(0.07, 0.07, 0.08))
	_part("Vest", torso_items, Vector3(0, 0.38, CHEST_Z - 0.012), Vector3(0.3, 0.3, 0.03), black)
	_part(
		"Pouch", torso_items, Vector3(0.08, 0.27, CHEST_Z - 0.035), Vector3(0.08, 0.07, 0.03), black
	)
	_part("Mask", head_items, Vector3(0, 0.12, FACE_Z - 0.006), Vector3(0.17, 0.1, 0.015), black)
	_part("Cap", head_items, Vector3(0, 0.33, 0.0), Vector3(0.2, 0.08, 0.2), black)


func _knife() -> Node3D:
	var knife := Node3D.new()
	knife.name = "Knife"
	_part(
		"Grip",
		knife,
		Vector3(0, 0, 0.0),
		Vector3(0.03, 0.03, 0.1),
		_material(Color(0.12, 0.1, 0.08))
	)
	_part(
		"Blade",
		knife,
		Vector3(0, 0, -0.14),
		Vector3(0.012, 0.035, 0.2),
		_material(Color(0.75, 0.77, 0.8))
	)
	return knife


func _pistol() -> Node3D:
	var pistol := Node3D.new()
	pistol.name = "Pistol"
	var metal := _material(Color(0.1, 0.1, 0.11))
	_part("Slide", pistol, Vector3(0, 0.04, -0.06), Vector3(0.035, 0.045, 0.2), metal)
	_part("Grip", pistol, Vector3(0, -0.02, 0.0), Vector3(0.03, 0.09, 0.045), metal)
	return pistol
