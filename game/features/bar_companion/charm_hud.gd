extends CanvasLayer
## One line above the wallet (bottom right) with the local player's charisma, mood,
## lucky night and escort goal. Hidden while there is nothing to report.

@onready var _label: Label = $Status


func _process(_delta: float) -> void:
	var companion := get_parent() as BarCompanion
	var peer := multiplayer.get_unique_id()
	var escorting := false
	var vivienne := companion.get_node_or_null("Vivienne")
	if vivienne != null:
		escorting = int(vivienne.get("net_escort")) == peer
	_label.text = status_text(
		companion.charisma_for(peer),
		companion.intoxication_for(peer),
		companion.luck_seconds_for(peer),
		escorting
	)
	_label.visible = not _label.text.is_empty()


static func status_text(charisma: int, intoxication: int, luck_s: int, escorting: bool) -> String:
	var parts: PackedStringArray = []
	if charisma > 0 or intoxication > 0:
		parts.append("Charisma %d (%s)" % [charisma, CharmMath.mood(intoxication)])
	if luck_s > 0:
		parts.append("Lucky night %d:%02d" % [luck_s / 60, luck_s % 60])
	if escorting:
		parts.append("Lead Vivienne to your room")
	return " · ".join(parts)
