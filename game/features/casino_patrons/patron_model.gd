class_name PatronModel
extends Node3D
## A casino patron on the shared player avatar rig (`BlockPlayerModel` from
## features/player_models): the same skinned mesh, textures and walk cycle as
## players, dressed in inventory clothing colors (`ClothingCatalog`). Small box
## accessories (ties, beards, glasses) ride the rig's head and torso pivots.
## Faces -Z with its feet at the origin. Cosmetic only: every peer builds and
## poses its own copy.

## The patron index that dresses up as Zohran Mamdani, New York City's mayor:
## dark suit, white shirt, blue tie, short black hair and a trimmed beard, with a
## name tag floating overhead.
const MAMDANI_LOOK := 4
const MAMDANI_NAME := "Zohran Mamdani"
const TRUMP_LOOK := 5
const TRUMP_NAME := "Donald Trump"
## Mitch McConnell rides a wheelchair pushed by his intern (`mitch.gd`); the intern
## is a second body built with INTERN_LOOK inside his model.
const MITCH_LOOK := 6
const MITCH_NAME := "Mitch McConnell"
const INTERN_LOOK := 7
## Salon guests (`salon_guest_model.gd`) pick from the looks after the intern.
const GUEST_LOOKS := 6

## The avatar rig is centred on a 1.8288 m player capsule.
const FEET_TO_BODY := 0.9144
## Hip joint height when standing (the rig's thigh bones sit 0.17 m below its centre).
const HIP_HEIGHT := FEET_TO_BODY - 0.17
## Thigh bone length of the rig, and the knee height that puts the soles on the floor.
const THIGH_LENGTH := 0.36
const SEATED_KNEE := 0.41
## Any speed below 55% of this reads as a walk, not a run.
const RIG_MAX_SPEED := 5.0
## Rig-space accessory anchors: face front, chest front.
const FACE_Z := -0.09
const CHEST_Z := -0.118

## skin: PlayerSkin index; hair: PlayerAppearance style and color; shirt/pants:
## ClothingCatalog color index (-1 for none); tie: ClothingCatalog color index or -1.
const LOOKS: Array[Dictionary] = [
	{"skin": 0, "hair": "classic", "hair_color": 0, "shirt": 1, "pants": 1, "tie": 11},
	{"skin": 3, "hair": "crop", "hair_color": 1, "shirt": 11, "pants": 9, "tie": 7},
	{"skin": 5, "hair": "classic", "hair_color": 0, "shirt": 6, "pants": 1, "tie": 3},
	{"skin": 7, "hair": "crop", "hair_color": 4, "shirt": 10, "pants": 9, "tie": 11},
	{"skin": 3, "hair": "crop", "hair_color": 0, "shirt": 1, "pants": 1, "tie": 3},
	{"skin": 1, "hair": "swept", "hair_color": 2, "shirt": 1, "pants": 1, "tie": 11},
	{"skin": 0, "hair": "crop", "hair_color": 4, "shirt": 1, "pants": 1, "tie": 3},
	{"skin": 0, "hair": "long", "hair_color": 2, "shirt": 0, "pants": 1, "tie": -1, "girl": true},
	# Salon guests: evening dresses and dinner suits.
	{"skin": 1, "hair": "long", "hair_color": 0, "shirt": 11, "pants": 11, "tie": -1, "girl": true},
	{"skin": 4, "hair": "classic", "hair_color": 0, "shirt": 1, "pants": 1, "tie": 7},
	{"skin": 2, "hair": "long", "hair_color": 3, "shirt": 5, "pants": 5, "tie": -1, "girl": true},
	{"skin": 6, "hair": "crop", "hair_color": 0, "shirt": 9, "pants": 1, "tie": 0},
	{"skin": 0, "hair": "long", "hair_color": 2, "shirt": 2, "pants": 2, "tie": -1, "girl": true},
	{"skin": 2, "hair": "swept", "hair_color": 4, "shirt": 10, "pants": 1, "tie": 3},
]

var avatar: BlockPlayerModel
## Accessory holders on the rig's torso and head pivots.
var torso_items: Node3D
var head_items: Node3D


## Builds the avatar with the look picked from `look` (the patron's index).
func build(look: int) -> void:
	dress_up(LOOKS[posmod(look, LOOKS.size())])
	var data: Dictionary = LOOKS[posmod(look, LOOKS.size())]
	var head := head_items
	var hair := _material(PlayerAppearance.HAIR_COLORS[int(data["hair_color"])])
	if look == MAMDANI_LOOK:
		_part("Beard", head, Vector3(0, 0.1, FACE_Z + 0.03), Vector3(0.15, 0.07, 0.07), hair)
		_part(
			"Moustache", head, Vector3(0, 0.155, FACE_Z + 0.005), Vector3(0.07, 0.015, 0.012), hair
		)
		_name_tag(MAMDANI_NAME)
	if look == TRUMP_LOOK:
		_part(
			"SweptFringe",
			head,
			Vector3(-0.02, 0.33, FACE_Z + 0.02),
			Vector3(0.17, 0.05, 0.06),
			hair
		)
		_name_tag(TRUMP_NAME)
	if look == MITCH_LOOK:
		var lens := _material(Color(0.05, 0.05, 0.06))
		for side: float in [-1.0, 1.0]:
			_part(
				"Lens%d" % int(side),
				head,
				Vector3(side * 0.035, 0.235, FACE_Z - 0.005),
				Vector3(0.045, 0.03, 0.008),
				lens
			)
		_name_tag(MITCH_NAME)
	if look == INTERN_LOOK:
		# A lanyard badge marks her as staff.
		_part(
			"Lanyard",
			torso_items,
			Vector3(0, 0.36, CHEST_Z - 0.005),
			Vector3(0.06, 0.08, 0.01),
			_material(ClothingCatalog.COLORS[3])
		)


## Builds the avatar from one `LOOKS`-shaped entry, with a tie when it names one.
func dress_up(data: Dictionary) -> void:
	avatar = BlockPlayerModel.new()
	avatar.name = "Avatar"
	avatar.position.y = FEET_TO_BODY
	avatar.set_body_type("girl" if data.get("girl", false) else "default")
	(
		avatar
		. set_appearance(
			{
				"skin": data["skin"],
				"hair": data["hair"],
				"hair_color": data["hair_color"],
				"eyes": 0,
				"outfit": "casual",
			}
		)
	)
	avatar.set_clothing(_clothing("shirt", data["shirt"]), _clothing("pants", data["pants"]))
	add_child(avatar)
	# BlockPlayerModel clears boxes parented straight to its pivots when it redecorates.
	torso_items = _pivot("Accessories", avatar._torso, Vector3.ZERO)
	head_items = _pivot("Accessories", avatar._head, Vector3.ZERO)
	var tie := int(data["tie"])
	if tie >= 0:
		var collar := _material(ClothingCatalog.COLORS[0])
		_part(
			"Collar",
			torso_items,
			Vector3(0, 0.56, CHEST_Z + 0.02),
			Vector3(0.1, 0.05, 0.02),
			collar
		)
		var knot := _material(ClothingCatalog.COLORS[tie])
		_part("Tie", torso_items, Vector3(0, 0.44, CHEST_Z), Vector3(0.045, 0.22, 0.012), knot)


## Poses the rig. `walk` is how much of a stride to take (0 standing, 1 walking);
## the rig advances its own stride phase from it. `limp` (0..1) blends into a
## sprawled, knocked-out pose; `flinch` (0..1) snaps the head back after a punch.
## `idle` slowly turns the head while standing about.
func pose(delta: float, walk: float, limp: float, flinch: float, idle: float) -> void:
	if avatar == null:
		return
	avatar.seated = false
	var alive := 1.0 - limp
	avatar.animate(delta, Vector3(0, 0, -walk * alive * PatronMath.WALK_SPEED), true, RIG_MAX_SPEED)
	avatar._head.rotation = Vector3(
		flinch * 0.5 - limp * 0.3, sin(idle * 0.7) * 0.5 * (1.0 - walk) * alive, limp * 0.6
	)
	if limp > 0.0:
		for i: int in 2:
			var side := -1.0 if i == 0 else 1.0
			var arm := avatar._left_arm if i == 0 else avatar._right_arm
			var leg := avatar._left_leg if i == 0 else avatar._right_leg
			var shin := avatar._left_shin if i == 0 else avatar._right_shin
			arm.rotation.z = side * 1.35 * limp
			arm.rotation.x = lerpf(arm.rotation.x, -0.5, limp)
			leg.rotation.z = side * 0.22 * limp
			shin.rotation.x = lerpf(shin.rotation.x, -0.9 if i == 0 else -0.15, limp)
	else:
		for arm: Node3D in [avatar._left_arm, avatar._right_arm]:
			arm.rotation.z = 0.0
		for leg: Node3D in [avatar._left_leg, avatar._right_leg]:
			leg.rotation.z = 0.0
	avatar.human.pose(avatar, false, false)


## Sits with the hip joints `hip_height` metres over the floor: thighs forward
## (dipping slightly when the seat is low enough for the feet to reach the floor),
## shins hanging straight down, upper arms `arm` radians forward with elbows bent
## `elbow`. `idle` turns the head. Call instead of `pose()`.
func sit(
	delta: float, hip_height: float, idle: float, arm: float = 0.35, elbow: float = -0.9
) -> void:
	if avatar == null:
		return
	avatar.seated = true
	avatar.animate(delta, Vector3.ZERO, true, RIG_MAX_SPEED)
	var thigh := seated_thigh(hip_height)
	for leg: Node3D in [avatar._left_leg, avatar._right_leg]:
		leg.rotation = Vector3(thigh, 0, 0)
	for shin: Node3D in [avatar._left_shin, avatar._right_shin]:
		shin.rotation.x = -thigh
	for upper: Node3D in [avatar._left_arm, avatar._right_arm]:
		upper.rotation = Vector3(arm, 0, 0)
	for forearm: Node3D in [avatar._left_forearm, avatar._right_forearm]:
		forearm.rotation.x = elbow
	avatar._rig.position.y = hip_height - HIP_HEIGHT
	avatar._torso.rotation = Vector3(-0.05, 0, 0)
	avatar._head.rotation = Vector3(0.05, sin(idle * 0.5) * 0.4, 0)
	avatar.human.pose(avatar, false, false)


## Thigh angle (radians forward of hanging) for a seat: level when the feet can't
## reach the floor, dipping up to ~27° so the soles rest on it from a low chair.
static func seated_thigh(hip_height: float) -> float:
	var dip := clampf((hip_height - SEATED_KNEE) / THIGH_LENGTH, 0.0, 0.45)
	return PI / 2.0 - asin(dip)


## Raises the right arm forward and up by `amount` (0..1), e.g. to pat a head.
## Call after `pose()`.
func reach(amount: float) -> void:
	if avatar == null or amount <= 0.0:
		return
	var arm := avatar._right_arm
	arm.rotation = arm.rotation.lerp(Vector3(1.3, 0, 0.1), amount)
	avatar._right_forearm.rotation.x = lerpf(avatar._right_forearm.rotation.x, -0.2, amount)
	avatar.human.pose(avatar, false, false)


## World position of a hand's wrist bone, following the skinned pose.
func hand_position(right: bool) -> Vector3:
	return bone_position("HandR" if right else "HandL")


## World position of one of the rig's skinned bones (e.g. "ThighL", "FootR").
func bone_position(bone: String) -> Vector3:
	var skeleton := avatar.human.skeleton
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	)


func _clothing(slot: String, color: int) -> String:
	return "" if color < 0 else "%s:%d" % [slot, color]


func _name_tag(text: String) -> void:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = text
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 40
	tag.outline_size = 10
	tag.pixel_size = 0.004
	tag.position = Vector3(0, 2.1, 0)
	add_child(tag)


func _pivot(label: String, parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = label
	pivot.position = at
	parent.add_child(pivot)
	return pivot


func _part(
	label: String, parent: Node3D, at: Vector3, dimensions: Vector3, material: Material
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	part.name = label
	part.mesh = box
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return material
