class_name OnlineStatue
extends Node3D
## Frozen avatar portrait. Leaderboard owns identity/history; this node only presents it.

const REFRESH_SECONDS := 60.0
const BRONZE := preload("res://features/leaderboard/statue_bronze.gdshader")
const GRAIN := preload("res://assets/casino_hub/textures/prop_grain.png")

@export var champion: Dictionary = {}:
	set(value):
		champion = value
		if is_node_ready():
			_present()
var _elapsed := REFRESH_SECONDS
var _model: BlockPlayerModel


func _ready() -> void:
	Network.mode_changed.connect(_reset)
	_present()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	var board := get_parent() as Leaderboard
	if board == null:
		return
	var next := board.longest_online()
	if next.is_empty():
		return
	_elapsed = 0.0
	if champion != next:
		champion = next


func _reset(_mode: Network.Mode) -> void:
	champion = {}
	_elapsed = REFRESH_SECONDS


static func portrait_for(tree: SceneTree, peer: int) -> Dictionary:
	var models := tree.get_first_node_in_group(&"player_models") as PlayerModels
	var result := {
		"body": "default",
		"head": "human",
		"tail": "none",
		"appearance": PlayerAppearance.defaults(),
		"height": 1.0,
		"shirt": "",
		"pants": "",
		"hat": ""
	}
	if models != null:
		result["body"] = models.type_for(peer)
		result["head"] = models.type_for_head(peer)
		result["tail"] = models.type_for_tail(peer)
		result["appearance"] = models.appearance_for(peer)
		result["height"] = models.height_scale_for(peer)
	var hand := Hand.for_peer(tree, peer)
	if hand != null and hand.inventory() != null:
		result["shirt"] = hand.inventory().shirt
		result["pants"] = hand.inventory().pants
		result["hat"] = hand.inventory().hat
	return result


static func valid_portrait(data: Dictionary) -> bool:
	if data.size() != 8:
		return false
	if not data.has_all(["body", "head", "tail", "appearance", "height", "shirt", "pants", "hat"]):
		return false
	if data["body"] not in PlayerModels.VALID_BODY_TYPES:
		return false
	if data["head"] not in PlayerModels.VALID_HEAD_TYPES:
		return false
	if data["tail"] not in PlayerModels.VALID_TAIL_TYPES:
		return false
	if not data["appearance"] is Dictionary or not PlayerAppearance.valid(data["appearance"]):
		return false
	var height: Variant = data["height"]
	if not (height is int or height is float) or not is_finite(float(height)):
		return false
	if float(height) < 0.5 or float(height) > 1.65:
		return false
	for slot: String in ["shirt", "pants", "hat"]:
		if not data[slot] is String:
			return false
		if data[slot] != "" and ClothingCatalog.slot(data[slot]) != slot:
			return false
	return true


func _present() -> void:
	if _model != null:
		_model.free()
		_model = null
	var label := get_node("Plaque") as Label3D
	label.text = "LONGEST ONLINE\nAwaiting a guest\nUpdated every minute"
	if champion.is_empty():
		return
	var seconds := maxi(0, int(champion.get("seconds", 0)))
	label.text = (
		"LONGEST ONLINE\n%s\n%dh %02dm\nUpdated every minute"
		% [str(champion.get("name", "Guest")), seconds / 3600, (seconds / 60) % 60]
	)
	var portrait: Dictionary = champion.get("portrait", {})
	if not valid_portrait(portrait):
		portrait = portrait_for(get_tree(), 0)
	_model = BlockPlayerModel.new()
	_model.name = "Portrait"
	add_child(_model)
	_model.set_body_type(portrait["body"])
	_model.set_head_type(portrait["head"])
	_model.set_tail_type(portrait["tail"])
	_model.set_appearance(portrait["appearance"])
	_model.set_clothing(portrait["shirt"], portrait["pants"])
	_model.set_hat(portrait["hat"])
	_model.animate(1.0, Vector3.ZERO, true, 8.0)
	PlayerHeight.apply_avatar(_model, float(portrait["height"]), 0.0)
	_model.position.y += 0.9
	var bronze := ShaderMaterial.new()
	bronze.shader = BRONZE
	bronze.set_shader_parameter("grain", GRAIN)
	var patina := bronze.duplicate() as ShaderMaterial
	patina.set_shader_parameter("patina", 0.7)
	var human_bronze := bronze.duplicate() as ShaderMaterial
	human_bronze.set_shader_parameter("human", true)
	human_bronze.set_shader_parameter("hide_head", _model.head_type != &"human")
	human_bronze.set_shader_parameter("face", SkinnedHuman.FACE)
	_bronze_meshes(_model, bronze, human_bronze, patina)


func _bronze_meshes(node: Node, bronze: Material, human_bronze: Material, patina: Material) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var original := mesh.material_override as StandardMaterial3D
		var dark := original != null and original.albedo_color.get_luminance() < 0.14
		mesh.material_override = human_bronze if node == _model.human.surface else bronze
		if dark:
			mesh.material_override = patina
	for child: Node in node.get_children():
		_bronze_meshes(child, bronze, human_bronze, patina)
