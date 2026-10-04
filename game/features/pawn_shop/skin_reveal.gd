class_name PrawnSkinReveal
extends Control
## A cosmetic decelerating reel. The server already committed the winning skin.

signal finished

const CARD_WIDTH := 116.0
const WINNER_INDEX := 12
const CARD := preload("res://features/pawn_shop/skin_reveal_card.gd")
var _strip: HBoxContainer
var _tween: Tween
var _generation := 0


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(0, 250)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func stop() -> void:
	_generation += 1
	if _tween != null:
		_tween.kill()
	hide()


func play(winner: String, odds: Array[int] = PrawnSkinCatalog.DEFAULT_ODDS) -> void:
	_generation += 1
	var generation := _generation
	if _tween != null:
		_tween.kill()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_strip = HBoxContainer.new()
	_strip.hide()
	_strip.add_theme_constant_override("separation", 0)
	add_child(_strip)
	var crate := ""
	for candidate: String in PrawnSkinCatalog.CRATES:
		if winner in PrawnSkinCatalog.CRATES[candidate]["skins"]:
			crate = candidate
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for index: int in 15:
		var id := winner
		if index != WINNER_INDEX:
			id = PrawnSkinCatalog.roll(crate, odds, rng.randi_range(0, 9999))
			if id.is_empty():
				id = winner
		var data: Array = PrawnSkinCatalog.SKINS[id]
		var box := CARD.new()
		box.rarity = PrawnSkinCatalog.COLORS[data[2]]
		box.custom_minimum_size = Vector2(CARD_WIDTH, 186)
		box.add_theme_constant_override("separation", 5)
		_strip.add_child(box)
		var icon := PrawnSkinIcon.new()
		icon.skin = id
		icon.custom_minimum_size = Vector2(96, 120)
		box.add_child(icon)
		var label := Label.new()
		label.text = data[0]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_color_override("font_color", PrawnSkinCatalog.COLORS[data[2]])
		label.add_theme_font_size_override("font_size", 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(label)
		var tier := Label.new()
		tier.text = PrawnSkinCatalog.TIERS[data[2]].to_upper()
		tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier.add_theme_font_size_override("font_size", 10)
		tier.add_theme_color_override("font_color", PrawnSkinCatalog.COLORS[data[2]])
		box.add_child(tier)
	# Showing a previously hidden VBox child queues a layout pass. Measure after it,
	# not at zero/stale width; this also centres the reel on phone-sized screens.
	await get_tree().process_frame
	if generation != _generation:
		return
	_strip.show()
	_strip.position.y = maxf(20, (size.y - 186) * 0.5)
	var marker := ColorRect.new()
	marker.color = Color("d4b060")
	marker.position = Vector2(size.x * .5 - 1, _strip.position.y - 14)
	marker.size = Vector2(2, 12)
	add_child(marker)
	var lower_marker := ColorRect.new()
	lower_marker.color = Color("d4b060")
	lower_marker.position = Vector2(size.x * .5 - 1, _strip.position.y + 189)
	lower_marker.size = Vector2(2, 12)
	add_child(lower_marker)
	_strip.position.x = size.x * .5 - CARD_WIDTH * .5
	var end := size.x * .5 - CARD_WIDTH * (WINNER_INDEX + .5)
	_tween = create_tween()
	_tween.tween_property(_strip, "position:x", end, 2.4).set_trans(Tween.TRANS_QUINT).set_ease(
		Tween.EASE_OUT
	)
	_tween.tween_callback(func() -> void: finished.emit())
