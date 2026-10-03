extends Node3D
## Cosmetic aura derived from the server's replicated boost; never grants luck.

var rings: Dictionary[int, MeshInstance3D] = {}
var mesh := TorusMesh.new()
var material := StandardMaterial3D.new()
var elapsed := 0.0
var music: AudioStreamPlayer
@onready var club: VipLounge = get_parent()


func _ready() -> void:
	mesh.inner_radius = 0.39
	mesh.outer_radius = 0.41
	mesh.rings = 12
	mesh.ring_segments = 24
	material.albedo_color = Color("e8c568")
	material.emission_enabled = true
	material.emission = Color("a67e28")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var glass := club.get_node("Interior/LuckyCoupe/Model") as MeshInstance3D
	var glass_finish := glass.material_override.duplicate() as StandardMaterial3D
	glass_finish.emission_enabled = true
	glass_finish.emission = Color("b68a30")
	glass.material_override = glass_finish
	music = AudioStreamPlayer.new()
	music.stream = preload("res://assets/vip_lounge/mirror_club.wav")
	music.volume_db = -23.0
	music.bus = GameAudio.BUS
	add_child(music)


func _process(delta: float) -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	var inside := bool(club.profile(multiplayer.get_unique_id()).get("inside", false))
	if inside and not music.playing:
		music.play()
	elif not inside and music.playing:
		music.stop()
	elapsed += delta
	var seen: Dictionary[int, bool] = {}
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer := player.get_multiplayer_authority()
		if int(club.profile(peer).get("luck", 0)) <= 0:
			continue
		seen[peer] = true
		if not rings.has(peer):
			var ring := MeshInstance3D.new()
			ring.mesh = mesh
			add_child(ring)
			rings[peer] = ring
		var ring := rings[peer]
		ring.global_position = (
			player.net_position - Vector3.UP * (player.movement.hull_height_m() * 0.5 - 0.04)
		)
		ring.scale = Vector3.ONE * (1.0 + sin(elapsed * 2.0) * 0.08)
	for peer: int in rings.keys():
		if not seen.has(peer):
			rings[peer].queue_free()
			rings.erase(peer)
