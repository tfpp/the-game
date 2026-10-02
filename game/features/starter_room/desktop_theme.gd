extends RefCounted
## Classic desktop chrome shared by the shell and its existing Jobs application.


static func bevel(pressed := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("c0c0c0")
	style.border_color = Color("ffffff") if not pressed else Color("606060")
	style.set_border_width_all(2)
	style.border_blend = false
	# Flat styles have one border colour; shadow supplies the opposite bevel edge.
	style.shadow_color = Color("606060") if not pressed else Color("ffffff")
	style.shadow_size = 1
	style.shadow_offset = Vector2(1, 1)
	style.set_content_margin_all(6)
	return style


static func create(font: Font) -> Theme:
	var result := Theme.new()
	result.default_font = font
	result.default_font_size = 16
	for type: String in ["Label", "Button", "LineEdit", "TextEdit", "PopupMenu"]:
		result.set_color("font_color", type, Color("181818"))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := bevel(state == "pressed")
		if state == "focus":
			style.border_color = Color("000080")
			style.bg_color = Color(0, 0, 0, 0)
		result.set_stylebox(state, "Button", style)
	result.set_color("font_hover_color", "Button", Color.BLACK)
	result.set_color("font_pressed_color", "Button", Color.BLACK)
	result.set_color("font_focus_color", "Button", Color.BLACK)
	result.set_color("font_disabled_color", "Button", Color("707070"))
	for type: String in ["LineEdit", "TextEdit"]:
		for state: String in ["normal", "focus"]:
			var style := bevel(true)
			style.bg_color = Color.WHITE
			result.set_stylebox(state, type, style)
		result.set_color("caret_color", type, Color.BLACK)
		result.set_color("selection_color", type, Color("809bc5"))
	for type: String in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color("909090")
		track.set_content_margin_all(7)
		result.set_stylebox("scroll", type, track)
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, bevel(state == "grabber_pressed"))
	result.set_constant("v_separation", "PopupMenu", 12)
	result.set_stylebox("panel", "PopupMenu", bevel())
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var selection := StyleBoxFlat.new()
	selection.bg_color = Color("000080")
	result.set_stylebox("hover", "PopupMenu", selection)
	return result
