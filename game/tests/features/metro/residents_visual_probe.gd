extends "res://features/metro/realm_preview.gd"
## Opt-in native review: station sleepers, cabin residents, seated first/third person.


func _ready() -> void:
	super._ready()
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	metro.net_time = 5
	var models := (load("res://features/player_models/feature.tscn") as PackedScene).instantiate()
	add_child(models)
	_capture_residents.call_deferred()


func _capture_residents() -> void:
	var zone := metro.stations[0]
	for frame: int in 5:
		await get_tree().process_frame
	var residents := zone._content.get_node("ShelteringResidents") as MetroResidents
	residents.update_view(1, true)
	camera.position = zone.position + Vector3(7.5, 2.6, 33)
	camera.look_at(zone.position + Vector3(11, 2.1, 30))
	await _save("platform")
	camera.position = zone.position + Vector3(0, 2.6, 3)
	camera.look_at(zone.position + Vector3(-0.5, 2.1, -5))
	await _save("cabin")
	var court := zone.seating
	# Near-side left bucket in the centre car; no resident occupies it.
	var index := 20
	player.global_position = court.stand_position(index) + Vector3.UP * 0.94
	player.net_position = player.global_position
	court.request_sit(index)
	court._physics_process(0.1)
	(player.get_node("Camera") as Camera3D).current = true
	await _save("first-person")
	camera.current = true
	camera.position = court.sit_position(index) + Vector3(1.0, 0.5, 1.5)
	camera.look_at(court.sit_position(index))
	await _save("third-person")
	get_tree().quit()


func _save(label: String) -> void:
	for frame: int in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/metro-residents-%s.png" % label)
