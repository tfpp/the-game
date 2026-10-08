extends Node
## Opt-in native-render review of casino drinks, drunk vision and blackouts.
## From game/ with a display:
##   godot --audio-driver Dummy --rendering-method gl_compatibility --resolution 1100x750 \
##     res://tests/features/booze/booze_visual_probe.tscn -- --offline
## Writes /tmp/booze-<view>.png for every view below; add --booze-view=<name> for one.
## "metro" runs a real blackout: collapse, metro drop-off and the lying wake-up.

const VIEWS := {
	"bar": [Vector3(-6.4, 0.55, -8.2), Vector3(-6.4, -0.12, -9.6)],
	"tables": [Vector3(-2.6, 0.4, -6.9), Vector3(-4.1, -0.31, -5.96)],
	"promenade": [Vector3(20.9, 1.9, -6.9), Vector3(20.245, 1.045, -7.82)],
	"lounge": [Vector3(-19.4, 1.9, 16.6), Vector3(-20.24, 1.045, 15.7)],
	"balcony": [Vector3(-28.0, 6.9, 1.0), Vector3(-29.38, 6.13, 1.0)],
	"lying": [Vector3(1.8, 1.4, 7.6), Vector3(3.5, 0.0, 5.0)],
}
const ITEMS: Array[String] = ["whiskey", "red_wine", "martini", "whiskey_rocks", "cosmopolitan"]

var _player: Player
var _camera := Camera3D.new()

@onready var _booze: Booze = $Game/Features/booze
@onready var _view: DrunkView = $Game/Features/booze/DrunkView


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	while _player == null:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group(&"local_player") as Player
	Controls.start()
	for layer: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		layer.queue_free()
	var day := $Game/Features/day_night as DayNight
	day.set_process(false)
	day._apply(0.5)
	for index: int in BoozeRules.SPOTS.size():
		var spot := _booze.get_node("Spots/Spot%d" % index) as DrinkSpot
		spot.net_item = ITEMS[index % ITEMS.size()]
	_player.global_position = Vector3(3.5, 0.95, 5.0)
	_player.net_position = _player.global_position
	add_child(_camera)
	var only := str(Network.args.get("booze-view", ""))
	for view: String in VIEWS:
		if only.is_empty() or view == only:
			await _capture_view(view)
	if only.is_empty() or only == "drunk":
		await _capture_drunk()
	if only.is_empty() or only == "metro":
		await _capture_metro()
	print("BOOZE_CAPTURE_PASS")
	get_tree().quit()


func _capture_view(view: String) -> void:
	if view == "lying":
		# Seen as another player sees it: third-person body, no local blackout screen.
		_view.process_mode = Node.PROCESS_MODE_DISABLED
		var third := get_tree().get_first_node_in_group(&"third_person_camera")
		third.set("enabled", true)
		var hand := Hand.for_peer(get_tree(), 1)
		hand.inventory().shirt = ""
		hand.inventory().pants = ""
		_booze._set_phase(1, BoozeRules.Phase.OUT)
	_camera.global_position = VIEWS[view][0]
	_camera.look_at(VIEWS[view][1])
	_camera.make_current()
	await get_tree().create_timer(1.2).timeout
	await _save(view)
	if view == "lying":
		_booze._clear(1)
		get_tree().get_first_node_in_group(&"third_person_camera").set("enabled", false)
		_view.process_mode = Node.PROCESS_MODE_INHERIT
		await get_tree().create_timer(2.0).timeout


func _capture_drunk() -> void:
	var bar := $Game/Features/bar_companion as BarCompanion
	for _i: int in 6:
		bar.add_drink(1)
	_view.level = 0.85
	_player.server_teleport.rpc_id(1, Vector3(-6.2, -0.3, -7.6), 0.0)
	_player.pitch = -0.25
	(_player.get_node("Camera") as Camera3D).make_current()
	await get_tree().create_timer(1.5).timeout
	await _save("drunk")


func _capture_metro() -> void:
	var bar := $Game/Features/bar_companion as BarCompanion
	for _i: int in 8:
		bar.add_drink(1)
	while _booze.phase_for(1) != BoozeRules.Phase.WAKE:
		await get_tree().process_frame
	while _booze.phase_elapsed(1) < 3.4:
		await get_tree().process_frame
	await _save("metro-wake-first-person")
	var third := get_tree().get_first_node_in_group(&"third_person_camera")
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_view._black.visible = false
	third.set("enabled", true)
	_camera.global_position = _player.global_position + Vector3(-1.6, 1.4, -2.2)
	_camera.look_at(_player.global_position + Vector3(0, -0.8, 0))
	_camera.make_current()
	await get_tree().create_timer(0.5).timeout
	await _save("metro-wake")
	print("BOOZE_METRO at ", _player.global_position)


func _save(view: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/booze-%s.png" % view)
