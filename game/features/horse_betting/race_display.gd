extends Node3D
## Tiny pixel broadcast on an existing monitor: only nearby clients redraw it.

const COLORS: Array[Color] = [Color("d8bd71"), Color("ae6657"), Color("78a8a0"), Color("baa5c5")]
var _track: Track
var _last_heading := ""
var _clock := 0.0

@onready var race: HorseBetting = get_parent()
@onready var heading: Label3D = $Heading
@onready var screen: MeshInstance3D = $Screen
@onready var broadcast: SubViewport = $Broadcast


func _ready() -> void:
	_track = Track.new()
	broadcast.add_child(_track)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = broadcast.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material


func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.1:
		return
	_clock = 0.0
	var local := get_tree().get_first_node_in_group(&"local_player") as Node3D
	var nearby := local != null and local.global_position.distance_to(global_position) < 40.0
	broadcast.render_target_update_mode = (
		SubViewport.UPDATE_ONCE if nearby else SubViewport.UPDATE_DISABLED
	)
	var title := "CROWN TURF CLUB\nUse terminal below — $1 / $5 / $10"
	match str(race.state["phase"]):
		"betting":
			title = (
				"CROWN TURF CLUB\nBets close in %ds · %d tickets"
				% [race.seconds_left, race.state["bets"].size()]
			)
		"racing":
			title = "CROWN TURF CLUB\nRACE IN PROGRESS — bets locked"
		"result", "idle":
			if int(race.state["winner"]) >= 0:
				title = (
					"WINNER: #%d %s\nUse terminal for tickets / results"
					% [
						int(race.state["winner"]) + 1,
						HorseBetting.HORSES[int(race.state["winner"])]
					]
				)
	if title != _last_heading:
		_last_heading = title
		heading.text = title
	if nearby:
		_track.positions = race.progress
		_track.running = race.state["phase"] == "racing"
		_track.frame += 1
		_track.queue_redraw()


class Track:
	extends Control
	var positions: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var running := false
	var frame := 0

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 128, 128), Color("15271e"))
		for lane: int in 4:
			var y := 22.0 + lane * 27.0
			draw_line(Vector2(2, y + 12), Vector2(126, y + 12), Color("627657"))
			for tile: int in 7:
				draw_rect(Rect2(112 + (tile % 2) * 3, y - 13 + tile * 4, 3, 4), Color.WHITE)
			var x := 12.0 + positions[lane] * 92.0
			var bob := float(frame % 2) if running else 0.0
			var color := COLORS[lane]
			# Side-on horse silhouette: rump, neck, muzzle, ear and tail, facing +X.
			var silhouette := PackedVector2Array(
				[
					Vector2(-8, -4),
					Vector2(3, -4),
					Vector2(5, -10),
					Vector2(7, -13),
					Vector2(8, -9),
					Vector2(12, -8),
					Vector2(12, -5),
					Vector2(7, -5),
					Vector2(5, 1),
					Vector2(-6, 1)
				]
			)
			for index: int in silhouette.size():
				silhouette[index] += Vector2(x, y + bob)
			draw_colored_polygon(silhouette, color)
			draw_line(Vector2(x - 7, y - 3), Vector2(x - 12, y + 2), color, 2)
			for leg: int in 4:
				var stride := (3.0 if (frame + leg) % 2 == 0 else -3.0) if running else 0.0
				var hip := Vector2(x - 5 + leg * 3, y)
				draw_line(hip, hip + Vector2(stride, 8), color, 2)
			# Saddle and jockey distinguish the numbered, color-coded entrants.
			draw_rect(Rect2(x - 3, y - 5 + bob, 5, 3), Color("38291f"))
			draw_circle(Vector2(x + 1, y - 10 + bob), 2, Color("eedcb2"))
			draw_line(Vector2(x, y - 8 + bob), Vector2(x + 4, y - 5 + bob), Color.WHITE, 2)
			draw_string(
				ThemeDB.fallback_font,
				Vector2(2, y - 5),
				str(lane + 1),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				8,
				color
			)
