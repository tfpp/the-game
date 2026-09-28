class_name GunMachineCabinet
extends Node3D
## The Gun-O-Matic's looks: a vending machine with a lit glass build chamber where a
## gantry mill and a robot arm machine each gun's parts and bolt them together, and a
## pickup tray below. Purely cosmetic and unnetworked, like explosion_effect.gd: the
## kiosk (gun_machine_kiosk.gd) tells every peer to `assemble()` the stats it just
## sold, and each peer animates its own copy. Between sales it idles with a demo gun.

const WIDTH := 1.0
const HEIGHT := 2.0
const DEPTH := 0.8
## Seconds to reveal every part of a gun, then how long the finished gun stays on the
## bench before it drops into the tray and the demo gun comes back.
const ASSEMBLY_DURATION := 2.4
const SHOWCASE_DURATION := 1.2
const DEMO_SEED := 159
const BENCH_HEIGHT := 1.0
const MILL_TRAVEL := 0.3

const SHELL_COLOR := Color(0.2, 0.28, 0.4)
const TRIM_COLOR := Color(0.75, 0.12, 0.1)
const DARK_COLOR := Color(0.08, 0.08, 0.09)
const STEEL_COLOR := Color(0.6, 0.62, 0.66)
const LAMP_COLOR := Color(1.0, 0.75, 0.25)

var _elapsed := 0.0
## Seconds since assemble() started, or -1 while idling.
var _assembly_time := -1.0
var _bench: Node3D
var _gun: Node3D
var _mill: Node3D
var _spindle: Node3D
var _arm: Node3D
var _spark: OmniLight3D


func _ready() -> void:
	_build_shell()
	_build_chamber()
	_show_gun(_demo_stats())


func _process(delta: float) -> void:
	_elapsed += delta
	var building := _assembly_time >= 0.0
	var speed := 4.0 if building else 1.0
	_mill.position.x = sin(_elapsed * 0.9 * speed) * MILL_TRAVEL
	_spindle.rotation.y += delta * (40.0 if building else 3.0)
	_arm.rotation.y = sin(_elapsed * 0.7 * speed) * 0.9
	_spark.visible = building and fmod(_elapsed, 0.12) < 0.06
	if not building:
		return
	_assembly_time += delta
	_reveal(parts_visible(_assembly_time, _part_count()))
	if _assembly_time >= ASSEMBLY_DURATION + SHOWCASE_DURATION:
		_assembly_time = -1.0
		_show_gun(_demo_stats())


## Starts building `stats`' gun on the bench, one part at a time.
func assemble(stats: Dictionary) -> void:
	_show_gun(stats)
	_assembly_time = 0.0
	_reveal(0)


func is_assembling() -> bool:
	return _assembly_time >= 0.0


## How many of `part_count` parts are visible `elapsed` seconds into an assembly.
static func parts_visible(elapsed: float, part_count: int) -> int:
	if elapsed < 0.0:
		return part_count
	var step := ASSEMBLY_DURATION / float(part_count)
	return clampi(int(elapsed / step) + 1, 1, part_count)


func bench_gun() -> Node3D:
	return _gun


func _part_count() -> int:
	return GunView.PART_NAMES.size()


func _reveal(count: int) -> void:
	if _gun == null:
		return
	for i: int in GunView.PART_NAMES.size():
		var part := _gun.get_node_or_null(NodePath(String(GunView.PART_NAMES[i]))) as Node3D
		if part != null:
			part.visible = i < count


func _show_gun(stats: Dictionary) -> void:
	if _gun != null:
		_bench.remove_child(_gun)
		_gun.queue_free()
	_gun = GunView.build(stats)
	_gun.name = "Gun"
	_bench.add_child(_gun)


static func _demo_stats() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = DEMO_SEED
	return GunGenerator.generate(rng)


func _build_shell() -> void:
	var shell := _material(SHELL_COLOR, 0.3)
	var trim := _material(TRIM_COLOR, 0.2)
	var dark := _material(DARK_COLOR)
	var steel := _material(STEEL_COLOR, 0.9)
	var half_w := WIDTH * 0.5
	var half_d := DEPTH * 0.5
	var inner_w := WIDTH - 0.16
	# Plinth, side walls, back wall and the illuminated header.
	_box(self, "Plinth", Vector3(WIDTH + 0.04, 0.12, DEPTH + 0.04), Vector3(0, 0.06, 0), dark)
	for side: float in [-1.0, 1.0]:
		_box(
			self,
			"Side",
			Vector3(0.08, HEIGHT - 0.12, DEPTH),
			Vector3(side * (half_w - 0.04), 0.12 + (HEIGHT - 0.12) * 0.5, 0),
			shell
		)
	_box(
		self, "Back", Vector3(inner_w, HEIGHT - 0.12, 0.04), Vector3(0, 1.06, -half_d + 0.02), shell
	)
	_box(self, "Header", Vector3(WIDTH, 0.3, DEPTH), Vector3(0, HEIGHT - 0.15, 0), trim)
	var sign_strip := _box(
		self,
		"SignStrip",
		Vector3(WIDTH - 0.12, 0.14, 0.02),
		Vector3(0, HEIGHT - 0.15, half_d + 0.01),
		_emissive(LAMP_COLOR)
	)
	sign_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lower cabinet: front panel with a pickup tray and a control panel.
	_box(
		self,
		"LowerPanel",
		Vector3(inner_w, BENCH_HEIGHT - 0.12, 0.04),
		Vector3(0, 0.12 + (BENCH_HEIGHT - 0.12) * 0.5, half_d - 0.02),
		shell
	)
	_box(self, "Tray", Vector3(0.5, 0.16, 0.12), Vector3(-0.1, 0.35, half_d + 0.02), dark)
	_box(self, "TrayLip", Vector3(0.52, 0.03, 0.14), Vector3(-0.1, 0.28, half_d + 0.03), steel)
	_box(self, "Controls", Vector3(0.18, 0.3, 0.04), Vector3(0.28, 0.65, half_d + 0.02), dark)
	_box(self, "CoinSlot", Vector3(0.02, 0.07, 0.01), Vector3(0.28, 0.72, half_d + 0.045), steel)
	var button := _box(
		self, "BuyButton", Vector3(0.07, 0.07, 0.02), Vector3(0.28, 0.58, half_d + 0.05), null
	)
	var button_mesh := CylinderMesh.new()
	button_mesh.top_radius = 0.035
	button_mesh.bottom_radius = 0.035
	button_mesh.height = 0.03
	button.mesh = button_mesh
	button.rotation.x = deg_to_rad(90.0)
	button.material_override = _emissive(TRIM_COLOR)
	# Glass front for the build chamber, framed in steel.
	var chamber_h := HEIGHT - 0.3 - BENCH_HEIGHT
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	_box(
		self,
		"Glass",
		Vector3(inner_w, chamber_h, 0.02),
		Vector3(0, BENCH_HEIGHT + chamber_h * 0.5, half_d - 0.02),
		glass
	)
	_box(self, "FrameLow", Vector3(inner_w, 0.03, 0.05), Vector3(0, BENCH_HEIGHT, half_d), steel)
	_box(
		self,
		"FrameHigh",
		Vector3(inner_w, 0.03, 0.05),
		Vector3(0, BENCH_HEIGHT + chamber_h, half_d),
		steel
	)


func _build_chamber() -> void:
	var steel := _material(STEEL_COLOR, 0.9)
	var dark := _material(DARK_COLOR)
	var trim := _material(TRIM_COLOR, 0.2)
	var top := HEIGHT - 0.3
	# Workbench with conveyor rollers.
	_box(
		self,
		"BenchTop",
		Vector3(WIDTH - 0.16, 0.04, DEPTH - 0.1),
		Vector3(0, BENCH_HEIGHT, 0),
		dark
	)
	for i: int in 6:
		var roller := _cylinder(self, 0.018, WIDTH - 0.2, steel)
		roller.rotation.z = deg_to_rad(90.0)
		roller.position = Vector3(0, BENCH_HEIGHT + 0.025, -0.25 + i * 0.1)
	_bench = Node3D.new()
	_bench.name = "Bench"
	_bench.position = Vector3(0, BENCH_HEIGHT + 0.2, 0.05)
	# Lie the gun across the chamber's width, shrunk so the longest barrels still fit.
	_bench.rotation.y = deg_to_rad(90.0)
	_bench.scale = Vector3.ONE * 0.5
	add_child(_bench)
	# Gantry mill: a beam across the top with a head that slides along it.
	_box(self, "Gantry", Vector3(WIDTH - 0.16, 0.05, 0.06), Vector3(0, top - 0.05, 0), steel)
	_mill = Node3D.new()
	_mill.name = "Mill"
	_mill.position = Vector3(0, top - 0.05, 0)
	add_child(_mill)
	_box(_mill, "Head", Vector3(0.12, 0.14, 0.12), Vector3(0, -0.09, 0), trim)
	_spindle = Node3D.new()
	_spindle.name = "Spindle"
	_spindle.position = Vector3(0, -0.2, 0)
	_mill.add_child(_spindle)
	var bit := _cylinder(_spindle, 0.015, 0.14, steel)
	bit.position = Vector3(0, -0.02, 0)
	var flute := _box(_spindle, "Flute", Vector3(0.04, 0.1, 0.008), Vector3(0, -0.03, 0), steel)
	flute.rotation.y = deg_to_rad(45.0)
	_spark = OmniLight3D.new()
	_spark.name = "Sparks"
	_spark.light_color = LAMP_COLOR
	_spark.light_energy = 2.0
	_spark.omni_range = 0.8
	_spark.position = Vector3(0, -0.12, 0)
	_spark.visible = false
	_spindle.add_child(_spark)
	# Robot arm on the back wall that swings parts onto the bench.
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(-0.3, BENCH_HEIGHT + 0.02, -0.25)
	add_child(_arm)
	var base := _cylinder(_arm, 0.06, 0.06, dark)
	base.position = Vector3(0, 0.03, 0)
	var upper := _box(_arm, "Upper", Vector3(0.04, 0.3, 0.04), Vector3(0, 0.2, 0.04), trim)
	upper.rotation.x = deg_to_rad(15.0)
	var fore := _box(_arm, "Fore", Vector3(0.035, 0.035, 0.26), Vector3(0, 0.34, 0.2), trim)
	fore.rotation.x = deg_to_rad(-10.0)
	for side: float in [-1.0, 1.0]:
		_box(_arm, "Claw", Vector3(0.01, 0.05, 0.03), Vector3(side * 0.02, 0.3, 0.34), steel)
	# Chamber light so the build is visible from the floor.
	var light := OmniLight3D.new()
	light.name = "ChamberLight"
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 1.2
	light.omni_range = 1.2
	light.position = Vector3(0, top - 0.12, 0.2)
	add_child(light)


static func _box(
	parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance, true)
	return instance


static func _cylinder(
	parent: Node3D, radius: float, height: float, material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.4 if metallic > 0.5 else 0.7
	return material


static func _emissive(color: Color) -> StandardMaterial3D:
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	return material
