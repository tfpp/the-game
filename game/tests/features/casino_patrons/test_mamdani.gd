extends GutTest
## Zohran Mamdani is one of the roaming casino patrons with his own look and name tag.


func test_mamdani_has_a_route() -> void:
	assert_gt(PatronMath.ROUTES.size(), PatronModel.MAMDANI_LOOK)


func test_mamdani_model_has_name_tag_and_beard() -> void:
	var model := PatronModel.new()
	add_child_autofree(model)
	model.build(PatronModel.MAMDANI_LOOK)
	var tag := model.get_node_or_null("NameTag") as Label3D
	assert_not_null(tag)
	if tag:
		assert_eq(tag.text, "Zohran Mamdani")
		assert_gt(tag.position.y, 1.9, "tag floats above the head")
	assert_not_null(model.find_child("Beard", true, false))


func test_other_patrons_keep_their_look() -> void:
	for look: int in PatronModel.MAMDANI_LOOK:
		var model := PatronModel.new()
		add_child_autofree(model)
		model.build(look)
		assert_null(model.get_node_or_null("NameTag"))
		assert_null(model.find_child("Beard", true, false))
