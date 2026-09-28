extends GutTest
## The "Hello" sign feature: a static prop placed in the room.

const HelloSignScene := preload("res://features/hello_sign/hello_sign.tscn")
const RoomScene := preload("res://world/room.tscn")


func test_sign_shows_hello() -> void:
	var sign := HelloSignScene.instantiate()
	var label := _find_label3d(sign)
	assert_not_null(label, "sign should contain a Label3D")
	if label:
		assert_eq(label.text, "Hello")
	sign.free()


func test_room_places_the_sign() -> void:
	var room := RoomScene.instantiate()
	assert_not_null(room.find_child("HelloSign", true, false))
	room.free()


func _find_label3d(node: Node) -> Label3D:
	if node is Label3D:
		return node as Label3D
	for child: Node in node.get_children():
		var found := _find_label3d(child)
		if found:
			return found
	return null
