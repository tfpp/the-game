extends GutTest
## Phase 1 task E2: casino and elevator signs are modeled SignBoards, not Label3D.

const INTERIOR := preload("res://features/casino_hub/interior.tscn")
const CAB := preload("res://features/elevator/elevator_cab.tscn")
const CASINO_SIGNS := [
	"WingSign-1",
	"WingSign1",
	"ZooTitle",
	"ZooNotice",
	"HarborTitle",
	"HarborNotice",
	"CasinoName",
	"CasinoDate",
	"Welcome",
	"Directions",
	"SecuritySign",
	"WardrobeSign",
	"RecreationSign",
	"TrampolineSign",
	"ExhibitSign",
]


func test_casino_interior_has_no_floating_labels() -> void:
	var interior := INTERIOR.instantiate() as Node3D
	add_child_autofree(interior)
	assert_eq(interior.find_children("*", "Label3D", true, false).size(), 0)
	for sign_name: String in CASINO_SIGNS:
		var sign := interior.get_node_or_null(sign_name) as SignBoard
		assert_not_null(sign, "%s is a SignBoard" % sign_name)
		if sign:
			assert_eq(sign.mount, SignBoard.Mount.FLUSH)
			var backings := sign.find_children("Backing", "", true, false)
			assert_eq(backings.size(), 1, "%s has a backing" % sign_name)
			assert_false(sign.text.contains("?"), "%s uses only atlas glyphs" % sign_name)


func test_casino_name_keeps_text() -> void:
	var interior := INTERIOR.instantiate() as Node3D
	add_child_autofree(interior)
	assert_eq((interior.get_node("CasinoName") as SignBoard).text, "THE GOLDEN CROWN")


func test_directional_arrows_are_in_atlas() -> void:
	assert_ne(SignLetterAtlas.index_of("<"), SignLetterAtlas.index_of("?"))
	assert_ne(SignLetterAtlas.index_of(">"), SignLetterAtlas.index_of("?"))
	assert_ne(SignLetterAtlas.index_of("<"), SignLetterAtlas.index_of(">"))


func test_elevator_signs_are_modeled_and_clear_the_lamp() -> void:
	var cab := CAB.instantiate() as ElevatorCab
	cab.sign_text = "LIFT"
	add_child_autofree(cab)
	assert_eq(cab.find_children("*", "Label3D", true, false).size(), 0)
	assert_eq((cab.get_node("Car/Sign") as SignBoard).text, "LIFT")
	var sign := cab.get_node("Car/Sign") as SignBoard
	var indicator := cab.get_node("Car/Indicator") as SignBoard
	assert_not_null(cab.get_node("Car/CabIndicator") as SignBoard)
	var sign_bottom := sign.position.y - sign.board_size().y * 0.5
	var indicator_top := indicator.position.y + indicator.board_size().y * 0.5
	assert_gt(sign_bottom, indicator_top, "sign and indicator do not overlap")
	var lamp := cab.get_node("Car/HallLamp") as Node3D
	assert_lt(indicator.position.x + indicator.board_size().x * 0.5, lamp.position.x - 0.12)
