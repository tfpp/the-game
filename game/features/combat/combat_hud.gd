extends CanvasLayer
## Shows the local player's health as a UI Pack - Space Expansion bar in the
## bottom-right corner (the one HUD corner core/ui's HUD leaves free) and a brief
## "You died" flash when combat.gd reports their death.

const DIED_FLASH_S := 2.0

var _died_timer := 0.0

@onready var _health: TextureProgressBar = $Health
@onready var _health_value: Label = $Health/Value
@onready var _died_label: Label = $Died


func _ready() -> void:
	_health.max_value = Combat.MAX_HEALTH
	var combat := get_parent() as Combat
	if combat != null:
		combat.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	var combat := get_parent() as Combat
	if combat != null:
		var hp := combat.health_for(multiplayer.get_unique_id())
		_health.value = hp
		_health_value.text = health_text(hp)
	if _died_timer > 0.0:
		_died_timer -= delta
		if _died_timer <= 0.0:
			_died_label.text = ""


## "75 HP". Rounds up so a sliver of health never reads as 0.
static func health_text(hp: float) -> String:
	return "%d HP" % ceili(maxf(hp, 0.0))


func _on_player_died(victim_peer: int, _attacker_peer: int) -> void:
	if victim_peer != multiplayer.get_unique_id():
		return
	_died_label.text = "You died"
	_died_timer = DIED_FLASH_S
