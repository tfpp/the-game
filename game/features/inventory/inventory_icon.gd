class_name InventoryIcon
extends Control
## Compact silhouettes drawn from the same clothing colors as the world models.

var _item := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(id: String) -> void:
	if id != _item:
		_item = id
		queue_redraw()


func _draw() -> void:
	var kind := ClothingCatalog.slot(_item)
	var color := ClothingCatalog.color(_item)
	if _item == "wallet":
		draw_circle(Vector2(12, 15), 11, Color("b68528"))
		draw_circle(Vector2(12, 13), 10, Color("edc64d"))
		draw_circle(Vector2(12, 13), 7, Color("f7de7c"), false, 1.5, true)
		draw_line(Vector2(12, 9), Vector2(12, 17), Color("ac7c23"), 2, true)
	elif kind == "shirt":
		var points := PackedVector2Array(
			[
				Vector2(20, 2),
				Vector2(8, 8),
				Vector2(12, 19),
				Vector2(20, 16),
				Vector2(20, 33),
				Vector2(44, 33),
				Vector2(44, 16),
				Vector2(52, 19),
				Vector2(56, 8),
				Vector2(44, 2),
				Vector2(39, 6),
				Vector2(25, 6),
			]
		)
		draw_colored_polygon(points, color)
	elif kind == "pants":
		draw_rect(Rect2(19, 2, 26, 10), color)
		draw_rect(Rect2(19, 10, 11, 24), color)
		draw_rect(Rect2(34, 10, 11, 24), color)
	elif ItemCatalog.consumable_kind(_item) == "beer":
		draw_rect(Rect2(25, 10, 14, 24), Color("634119"))
		draw_rect(Rect2(29, 1, 6, 12), Color("634119"))
		draw_rect(Rect2(25, 18, 14, 10), Color("d4ba78"))
	elif ItemCatalog.consumable_kind(_item) == "cigarette":
		draw_line(Vector2(12, 24), Vector2(48, 10), Color("e3d9ba"), 5, true)
		draw_line(Vector2(39, 14), Vector2(48, 10), Color("a65c21"), 5, true)
	elif _item == "banana":
		draw_arc(Vector2(30, 5), 22, 0.15, 2.5, 16, Color("ebc64c"), 9, true)
	elif _item == "ball":
		draw_circle(Vector2(32, 18), 16, Color("df792c"))
		draw_line(Vector2(16, 18), Vector2(48, 18), Color("533e33"), 2, true)
		draw_line(Vector2(32, 2), Vector2(32, 34), Color("533e33"), 2, true)
	elif not _item.is_empty():
		var metal := Color("354656")
		draw_rect(Rect2(12, 9, 40, 9), metal)
		draw_rect(Rect2(17, 16, 8, 15), metal)
		if _item in ["shotgun", "awp", "smg"]:
			draw_rect(Rect2(3, 12, 13, 10), Color("946849"))
			draw_rect(Rect2(35, 12, 24, 4), metal)
		if _item == "awp":
			draw_rect(Rect2(20, 3, 22, 4), metal)
