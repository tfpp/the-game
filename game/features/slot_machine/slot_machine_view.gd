extends Node3D
## Physical cabinet and animated reel drums. Presentation reads authoritative results.

const CABINET := preload("res://features/casino_hub/models/slot_cabinet.tscn")
const REEL_SHADER := preload("res://features/slot_machine/reel.gdshader")
const SYMBOL_TEXTURE := preload("res://features/slot_machine/textures/reel_symbols.png")
const CHROME := preload("res://features/casino_hub/materials/chrome.tres")
const SYMBOLS: Array[String] = ["7", "BAR", "STAR", "BELL", "GEM"]
const GOLD := Color("f6c85f")
const INK := Color("173330")

var _reels: Array[ShaderMaterial] = []
var _positions: Array[float] = [0.0, 1.0, 2.0]
var _targets: Array[float] = [0.0, 1.0, 2.0]
var _status: Label3D
var _caption: Label3D
var _lever: Node3D
var _last_state: Dictionary = {}

@onready var _machine: SlotMachine = get_parent() as SlotMachine


func _ready() -> void:
	add_child(CABINET.instantiate())
	_label("LUCKY FIVE", Vector3(0, 2.49, 0.596), 48, INK, 0.004)
	_label("THE GILDED LILY  •  EST. 1964", Vector3(0, 2.38, 0.596), 18, INK, 0.003)
	var drum := SlotReelMesh.create()
	for index: int in 3:
		var reel := MeshInstance3D.new()
		reel.name = "Reel%d" % index
		reel.mesh = drum
		reel.position = Vector3(float(index - 1) * 0.58, 1.73, 0.26)
		var material := ShaderMaterial.new()
		material.shader = REEL_SHADER
		material.set_shader_parameter("symbols", SYMBOL_TEXTURE)
		material.set_shader_parameter("reel_position", float(index))
		reel.material_override = material
		_reels.append(material)
		add_child(reel)
	# Small red payline pointers, outside the clear viewing area.
	_label("▶", Vector3(-0.91, 1.73, 0.655), 25, Color("ba293a"), 0.003)
	_label("◀", Vector3(0.91, 1.73, 0.655), 25, Color("ba293a"), 0.003)
	_status = _label("TRY YOUR LUCK", Vector3(-0.18, 0.94, 0.56), 26, GOLD, 0.0025)
	_caption = _label(_price_caption(), Vector3(0, 2.245, 0.56), 21, GOLD, 0.0025)
	_label("7  ×30    BAR  ×20    STAR  ×10", Vector3(0, 0.72, 0.505), 18, GOLD, 0.0025)
	_label("BELL  ×15    GEM  ×25    PAIRS  ×0", Vector3(0, 0.65, 0.505), 18, GOLD, 0.0025)
	_label("THREE MATCHING SYMBOLS PAY", Vector3(0, 0.58, 0.505), 13, Color("ded2b9"), 0.0025)
	_build_lever()


func _process(delta: float) -> void:
	var snapshot := _machine.state
	if snapshot != _last_state:
		_update_snapshot(snapshot)
	var spinning: bool = snapshot["spinning"]
	for index: int in 3:
		if spinning and index >= int(snapshot["stopped"]):
			_positions[index] = fposmod(_positions[index] + delta * (13.0 + index), 5.0)
		else:
			_positions[index] = move_toward(_positions[index], _targets[index], delta * 36.0)
		_reels[index].set_shader_parameter("reel_position", _positions[index])
	_lever.rotation.x = lerpf(_lever.rotation.x, 0.8 if spinning else 0.0, 1.0 - exp(-delta * 14.0))


func _update_snapshot(snapshot: Dictionary) -> void:
	var reels: Array = snapshot["reels"]
	for index: int in 3:
		if _last_state.is_empty():
			_positions[index] = float(reels[index])
			_targets[index] = _positions[index]
		elif index < int(snapshot["stopped"]):
			var newly_stopped := index >= int(_last_state.get("stopped", 3))
			if newly_stopped or not bool(snapshot["spinning"]):
				_targets[index] = SlotReelMesh.next_stop(_positions[index], int(reels[index]))
	_last_state = snapshot.duplicate(true)
	if not str(snapshot.get("message", "")).is_empty():
		_status.text = str(snapshot["message"])
	elif snapshot["spinning"]:
		_status.text = "GOOD LUCK"
	elif int(snapshot["spin"]) > 0:
		_status.text = (
			("WON %s" % PlayerMoney.format_money(int(snapshot["payout"])))
			if snapshot["won"]
			else "PLAY AGAIN"
		)
	else:
		_status.text = "TRY YOUR LUCK"
	_caption.text = _price_caption()
	# Keep even billion-dollar buy-ins and long server messages inside their panels.
	_fit_label(_status, 1.18, 0.0025)
	_fit_label(_caption, 1.68, 0.0025)


func _price_caption() -> String:
	return "%s PER SPIN" % PlayerMoney.format_money(_machine.buy_in_cents)


func _build_lever() -> void:
	_lever = Node3D.new()
	_lever.position = Vector3(1.14, 1.23, 0.0)
	add_child(_lever)
	var stem := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.038
	cylinder.bottom_radius = 0.055
	cylinder.height = 0.65
	cylinder.radial_segments = 24
	stem.mesh = cylinder
	stem.position.y = 0.3
	stem.material_override = CHROME
	_lever.add_child(stem)
	var knob := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.115
	sphere.height = 0.23
	knob.mesh = sphere
	knob.position.y = 0.67
	var bakelite := StandardMaterial3D.new()
	bakelite.albedo_color = Color("8d172c")
	bakelite.roughness = 0.23
	knob.material_override = bakelite
	_lever.add_child(knob)


func _label(
	text: String, origin: Vector3, font_size: int, color: Color, pixel_size: float
) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = origin
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	add_child(label)
	return label


func _fit_label(label: Label3D, width: float, maximum_pixel_size: float) -> void:
	var font := ThemeDB.fallback_font
	var pixels := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	label.pixel_size = minf(maximum_pixel_size, width / maxf(pixels, 1.0))
