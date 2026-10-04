extends CanvasLayer
## Local health bar and an automatic death screen. Only the server's respawn
## completion closes the screen; clients cannot shorten the respawn delay. The bar is
## placed by ui/hud_layout.gd under the wallet (features/money).

var _placed_for := ""

@onready var _health: ProgressBar = $Health
@onready var _health_value: Label = $Health/Value
@onready var _death_screen: ColorRect = $DeathScreen


func _ready() -> void:
	_health.max_value = Combat.MAX_HEALTH
	var combat := get_parent() as Combat
	if combat != null:
		combat.player_died.connect(_on_player_died)
		combat.player_respawned.connect(_on_player_respawned)
	Network.mode_changed.connect(_on_mode_changed)


func _exit_tree() -> void:
	_close_death_screen()


func _process(_delta: float) -> void:
	var key := HudLayout.layout_key(self)
	if key != _placed_for:
		_placed_for = key
		HudLayout.place(_health, HudLayout.Piece.HEALTH)
	var combat := get_parent() as Combat
	if combat != null:
		var hp := combat.health_for(multiplayer.get_unique_id())
		_health.value = hp
		_health_value.text = health_text(hp)


## "75 HP". Rounds up so a sliver of health never reads as 0.
static func health_text(hp: float) -> String:
	return "%d HP" % ceili(maxf(hp, 0.0))


func _on_player_died(victim_peer: int, _attacker_peer: int) -> void:
	if victim_peer != multiplayer.get_unique_id() or _death_screen.visible:
		return
	_death_screen.show()
	add_to_group(&"modal_ui")
	# No buttons: retain browser pointer lock so the timed respawn does not need
	# a new user gesture to recapture it. The modal group blocks gameplay input.
	Controls.clear_input()


func _on_player_respawned(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_close_death_screen()


func _on_mode_changed(_mode: Network.Mode) -> void:
	_close_death_screen()


func _close_death_screen() -> void:
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	if is_instance_valid(_death_screen):
		_death_screen.hide()
