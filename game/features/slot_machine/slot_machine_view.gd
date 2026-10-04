extends Node3D
## Physical cabinet and animated reel drums. Presentation reads authoritative results.

const FEEDBACK := preload("res://features/slot_machine/slot_feedback.gd")
const CABINET := preload("res://features/casino_hub/models/slot_cabinet.tscn")
const REEL_SHADER := preload("res://features/slot_machine/reel.gdshader")
const SYMBOL_TEXTURE := preload("res://assets/slot_machine/textures/reel_symbols.png")
const LEVER_MESH := preload("res://assets/slot_machine/cabinet_v2/lever.res")
const CABINET_FINISH := preload("res://features/slot_machine/materials/cabinet_v2.tres")
const SYMBOLS: Array[String] = ["7", "BAR", "STAR", "BELL", "GEM"]
const GOLD := Color("f6c85f")
const INK := Color("f9cc66")

var feedback: Node3D
var _reels: Array[ShaderMaterial] = []
var _positions: Array[float] = [0.0, 1.0, 2.0]
var _targets: Array[float] = [0.0, 1.0, 2.0]
var _status: Label3D
var _caption: Label3D
var _lever: Node3D
var _last_state: Dictionary = {}
var _pull_age := 1.0
var _settle_age: Array[float] = [1.0, 1.0, 1.0]
var _settle_from: Array[float] = [0.0, 1.0, 2.0]

@onready var _machine: SlotMachine = get_parent() as SlotMachine


func _ready() -> void:
	add_child(CABINET.instantiate())
	_art_panel(Vector3(0, 2.3875, .333), Vector2(1.20, .635), Rect2(2, 2, 124, 72))
	_art_panel(Vector3(0, .885, .512), Vector2(1.20, .45), Rect2(2, 78, 124, 48))
	_plaque("LUCKY FIVE", Vector3(0, 2.60, .345), .085)
	_plaque("THE GOLDEN CROWN", Vector3(0, .85, .525), .055)
	var drum := SlotReelMesh.create()
	for index: int in 3:
		var reel := MeshInstance3D.new()
		reel.name = "Reel%d" % index
		reel.mesh = drum
		reel.position = Vector3(float(index - 1) * .36, 1.6744, .2042)
		reel.rotation.x = -.30
		reel.scale = Vector3(.54, .49, .53)
		var material := ShaderMaterial.new()
		material.shader = REEL_SHADER
		material.set_shader_parameter("symbols", SYMBOL_TEXTURE)
		material.set_shader_parameter("reel_position", float(index))
		reel.material_override = material
		_reels.append(material)
		add_child(reel)
	_status = _label("READY", Vector3(0, 1.505, .56), 20, Color("ff6a3f"), .002)
	_caption = _label(_price_caption(), Vector3(0, 2.012, .365), 16, GOLD, .002)
	_plaque("7 X30  BAR X20  STAR X10  BELL X15  GEM X25", Vector3(0, .672, .527), .026)
	var controls: Array[String] = ["BET", "MAX", "COLLECT", "SERVICE", "SPIN"]
	for i: int in 5:
		var label := _plaque(controls[i], Vector3(-.48 + i * .23, 1.416, .724), .022)
		label.rotation.x = -.58
	_plaque("INSERT BILLS", Vector3(.465, 1.243, .771), .015)
	_build_lever()
	feedback = FEEDBACK.new()
	feedback.name = "Feedback"
	add_child(feedback)
	_build_glass()


func _process(delta: float) -> void:
	var snapshot := _machine.state
	if snapshot != _last_state:
		_update_snapshot(snapshot)
	feedback.update(snapshot, delta)
	_pull_age += delta
	var spinning: bool = snapshot["spinning"]
	for index: int in 3:
		var previous := _positions[index]
		if spinning and index >= int(snapshot["stopped"]):
			_positions[index] = fposmod(_positions[index] + delta * (13.0 + index), 5.0)
		else:
			_settle_age[index] += delta
			var t := minf(1, _settle_age[index] / .18)
			var ease := 1.0 - pow(1.0 - t, 3)
			_positions[index] = lerpf(_settle_from[index], _targets[index], ease)
			# A small damped mechanical detent; never changes the chosen symbol.
			_positions[index] += sin(t * TAU) * .07 * (1 - t)
		if not is_equal_approx(previous, _positions[index]):
			_reels[index].set_shader_parameter("reel_position", _positions[index])
	var pull := 0.0
	if _pull_age < .22:
		pull = .95 * sin(clampf(_pull_age / .22, 0, 1) * PI * .5)
	elif _pull_age < .65:
		pull = .95 * pow(1 - (_pull_age - .22) / .43, 2)
	_lever.rotation.x = pull


func _update_snapshot(snapshot: Dictionary) -> void:
	var reels: Array = snapshot["reels"]
	var first := _last_state.is_empty()
	var new_spin := int(snapshot["spin"]) > int(_last_state.get("spin", 0))
	if new_spin and bool(snapshot["spinning"]):
		_pull_age = 0
	for index: int in 3:
		var stopped := index < int(snapshot["stopped"])
		var newly_stopped := stopped and index >= int(_last_state.get("stopped", 3))
		if first or not bool(snapshot["spinning"]) or int(snapshot["spin"]) == 0:
			_positions[index] = float(reels[index])
			_targets[index] = _positions[index]
			_settle_from[index] = _positions[index]
			_settle_age[index] = 1
		elif newly_stopped:
			_settle_from[index] = _positions[index]
			_targets[index] = SlotReelMesh.next_stop(_positions[index], int(reels[index]))
			_settle_age[index] = 0
	for index: int in 3:
		_reels[index].set_shader_parameter("reel_position", _positions[index])
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
		_status.text = "READY"
	_caption.text = _price_caption()
	# Keep even billion-dollar buy-ins and long server messages inside their panels.
	_fit_label(_status, 1.05, 0.002)
	_fit_label(_caption, 1.12, 0.002)


func _price_caption() -> String:
	return "%s PER SPIN" % PlayerMoney.format_money(_machine.buy_in_cents)


func _build_lever() -> void:
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = Vector3(.76, 1.48, .18)
	_lever.scale = Vector3.ONE * .70
	add_child(_lever)
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = LEVER_MESH
	model.material_override = CABINET_FINISH
	_lever.add_child(model)


func _plaque(text: String, origin: Vector3, height: float) -> SignBoard:
	var plaque := SignBoard.new()
	plaque.text = text
	plaque.position = origin
	plaque.letter_height = height
	plaque.padding = .01
	add_child(plaque)
	return plaque


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


func _build_glass() -> void:
	var glass := MeshInstance3D.new()
	var pane := QuadMesh.new()
	pane.size = Vector2(1.18, .49)
	glass.mesh = pane
	glass.position = Vector3(0, 1.735, .412)
	glass.rotation.x = -.30
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.45, .65, .60, .045)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.material_override = material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)


func _art_panel(at: Vector3, dimensions: Vector2, chart: Rect2) -> void:
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = dimensions
	panel.mesh = quad
	panel.position = at
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = preload("res://assets/slot_machine/cabinet_v3/glass.png")
	paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	paint.uv1_scale = Vector3(chart.size.x / 128, chart.size.y / 128, 1)
	paint.uv1_offset = Vector3(chart.position.x / 128, chart.position.y / 128, 0)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.roughness = .45
	panel.material_override = paint
	add_child(panel)
