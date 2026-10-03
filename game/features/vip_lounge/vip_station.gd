class_name VipStation
extends Node3D
## Stable interaction endpoint on every peer. Models and dialogue are local visuals.

const HOST_LINES := {
	"Scarlett":
	["The view is better up here. So are the drinks.", "Back already? I saved your favorite view."],
	"Jade":
	[
		"Feeling lucky? I've been saving something for you.",
		"Ask quietly and I'll show you the Whisper Menu."
	],
	"Valentina":
	[
		"Meet our three hosts, try a table, and find the crown behind the glass.",
		"Some people chase the jackpot. I prefer good company."
	]
}
const STOCK := {
	"Scarlett": ["gift"],
	"Jade": ["luck", "golden", "velvet"],
	"Valentina": ["mission", "shirt", "pants"],
	"Private Table": ["play"],
	"Crown Symbol": ["symbol"]
}

@export var host_name := "Scarlett"
@export var dress := 11
@export var hair_color := 0
@export var age := 28
var model: CompanionModel
var speech: Label3D
var speech_left := 0.0
var idle := 0.0
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var club: VipLounge = get_parent()


func _ready() -> void:
	add_to_group(&"interactables")
	entity.interaction_range = 2.8
	entity.interaction_offset = Vector3(0, 1, 0)
	entity.register_use(can_use, _open, 0.5)
	entity.register_action(&"service", _may_act, _act, 0.5)
	entity.event_received.connect(_event)
	if host_name in HOST_LINES:
		model = CompanionModel.new()
		model.name = "Model"
		add_child(model)
		model.build_evening_guest(host_name, dress, hair_color, "long")
		speech = Label3D.new()
		speech.position.y = 2.5
		speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		speech.pixel_size = 0.003
		speech.font_size = 28
		speech.modulate = Color("f1cd9b")
		speech.visible = false
		add_child(speech)


func interaction_text() -> String:
	return "Talk to " + host_name if host_name in HOST_LINES else "Use " + host_name


func can_use(player: Player) -> bool:
	return (
		player != null
		and entity.in_range(player)
		and club.admitted(player.get_multiplayer_authority())
		and VipLounge.BOUNDS.has_point(player.net_position)
	)


func use() -> void:
	entity.request_use()


func _open(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if host_name == "Crown Symbol":
		return club.act(peer, "symbol", {}, entity)
	return club.talk(peer, host_name, entity)


func _may_act(peer: int, payload: Dictionary) -> bool:
	if (
		payload.size() != 2
		or not payload.get("action") is String
		or not payload.get("options") is Dictionary
	):
		return false
	var action: String = payload["action"]
	return (
		action in STOCK.get(host_name, [])
		and can_use(entity.player_for_peer(peer))
		and club.allowed(peer, action, payload["options"])
	)


func _act(peer: int, payload: Dictionary) -> bool:
	return club.act(peer, payload["action"], payload["options"], entity)


func _event(event: StringName, _payload: Dictionary) -> void:
	if event == &"menu" and speech != null:
		var row := club.profile(multiplayer.get_unique_id())
		var repeat := int(row.get("visits", 0)) > 1
		speech.text = HOST_LINES[host_name][1 if repeat else 0]
		speech.visible = true
		speech_left = 5.0
	elif event == &"clink" and Network.mode != Network.Mode.SERVER:
		GameAudio.play_at(self, &"pickup", global_position)


func _process(delta: float) -> void:
	# GPS's object catalog reads interactables. Reveal upstairs services only once
	# this client discovers the lounge; the dedicated server keeps its endpoints.
	var discovered := bool(club.profile(multiplayer.get_unique_id()).get("discovered", false))
	if Network.mode == Network.Mode.SERVER or discovered:
		add_to_group(&"interactables")
	else:
		remove_from_group(&"interactables")
	idle += delta
	if model != null:
		model.pose(delta, 0, 0, 0, sin(idle * 0.6) * 0.18)
	if speech != null:
		speech_left -= delta
		speech.visible = speech_left > 0.0
