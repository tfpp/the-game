extends SceneTree
## Migrate only the saved east upper wall section, preserving other authored nodes.

const CASINO := "res://features/casino_hub/casino_gridmap.tscn"
const RECESS := preload("res://features/casino_hub/gridmap/vip_window.gd")


func _initialize() -> void:
	var level := (load(CASINO) as PackedScene).instantiate() as Node3D
	RECESS.configure(level)
	var packed := PackedScene.new()
	assert(packed.pack(level) == OK)
	var temporary := "user://vip-casino-migration.tscn"
	assert(ResourceSaver.save(packed, temporary) == OK)
	var generated := FileAccess.get_file_as_string(temporary)
	var original := FileAccess.get_file_as_string(CASINO)
	var marker := '[node name="UpperWallsEastWest"'
	var start := original.find("data = {", original.find(marker))
	var end := original.find("\n}", start) + 2
	var updated := generated.find("data = {", generated.find(marker))
	var updated_end := generated.find("\n}", updated) + 2
	assert(start >= 0 and end > start and updated >= 0 and updated_end > updated)
	original = (
		original.substr(0, start)
		+ generated.substr(updated, updated_end - updated)
		+ original.substr(end)
	)
	if not original.contains('id="vip_window"'):
		original = (original.replace(
			"[gd_scene format=3]",
			(
				'[gd_scene format=3]\n\n[ext_resource type="PackedScene" '
				+ 'path="res://features/vip_lounge/window.tscn" id="vip_window"]'
			)
		))
		original += (
			'\n[node name="VipWindow" parent="." instance=ExtResource("vip_window")]\n'
			+ "position = Vector3(24, 6.875, 0)\n"
		)
	var file := FileAccess.open(CASINO, FileAccess.WRITE)
	assert(file != null)
	file.store_string(original)
	file.close()
	level.free()
	DirAccess.remove_absolute(temporary)
	await process_frame
	print("VIP recess: saved casino upper wall opening and sealed window")
	quit()
