extends GutTest
## Covers the head and tail axes added to Character Model: independent of body type,
## mixable into an "impossible creature" (see player_models/README.md).

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const FEATURE_SCENE := preload("res://features/player_models/feature.tscn")

var _player: Player
var _feature: Node
var _model: BlockPlayerModel


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_feature = FEATURE_SCENE.instantiate()
	add_child_autofree(_feature)
	_feature._process(0.0)
	_model = _player.get_node("Body/Avatar") as BlockPlayerModel
	_model.set_process(false)


func test_unrecognized_head_and_tail_types_fall_back_to_defaults() -> void:
	_model.set_head_type("frog")
	_model.set_tail_type("lizard")
	_model.set_head_type("not-a-real-head")
	_model.set_tail_type("not-a-real-tail")
	assert_eq(_model.head_type, &"human")
	assert_eq(_model.tail_type, &"none")


func test_frog_head_replaces_human_face_and_hair() -> void:
	assert_not_null(_model.get_node_or_null("Rig/Torso/Head/HairBack"))
	_model.set_head_type("frog")
	assert_eq(_model.head_type, &"frog")
	assert_null(_model.get_node_or_null("Rig/Torso/Head/HairBack"), "Frog head has no hair")
	assert_not_null(_model.get_node_or_null("Rig/Torso/Head/Snout"))


func test_bird_head_is_distinct_from_the_penguin_costume() -> void:
	_model.set_head_type("bird")
	assert_eq(_model.head_type, &"bird")
	assert_not_null(_model.get_node_or_null("Rig/Torso/Head/Beak"))
	assert_almost_eq(_model.height_scale(), 1.0, 0.0001, "A bird head alone keeps human height")


func test_penguin_body_ignores_head_type_and_keeps_its_own_head() -> void:
	_model.set_head_type("frog")
	_model.set_body_type("penguin")
	assert_null(_model.get_node_or_null("Rig/Torso/Head/Snout"), "Penguin body ignores head type")
	assert_not_null(_model.get_node_or_null("Rig/Torso/Head/Beak"))


func test_tail_types_attach_and_clear_independently_of_body_and_head() -> void:
	assert_null(_model.get_node_or_null("Rig/Torso/Tail/Base"))
	_model.set_tail_type("fin")
	assert_eq(_model.tail_type, &"fin")
	assert_not_null(_model.get_node_or_null("Rig/Torso/Tail/Base"))
	_model.set_tail_type("fluffy")
	assert_null(
		_model.get_node_or_null("Rig/Torso/Tail/Base"), "Switching tails clears the old one"
	)
	assert_not_null(_model.get_node_or_null("Rig/Torso/Tail/Puff"))
	_model.set_body_type("penguin")
	assert_not_null(
		_model.get_node_or_null("Rig/Torso/Tail/Puff"), "Tails still show on the penguin costume"
	)
	_model.set_tail_type("none")
	assert_null(_model.get_node_or_null("Rig/Torso/Tail/Puff"))


func test_mixed_creature_preserves_clothing_and_skin_across_all_three_choices() -> void:
	_model.set_clothing("shirt:4", "pants:3")
	_model.set_skin_index(7)
	_model.set_body_type("girl")
	_model.set_head_type("frog")
	_model.set_tail_type("lizard")
	assert_eq(_model.body_type, &"girl")
	assert_eq(_model.head_type, &"frog")
	assert_eq(_model.tail_type, &"lizard")
	assert_eq(_model.shirt_color, ClothingCatalog.COLORS[4])
	assert_eq(_model.pants_color, ClothingCatalog.COLORS[3])
	assert_eq(_model.skin_color, PlayerSkin.TONES[7])
	assert_not_null(_model.get_node_or_null("Rig/Torso/Tail/Segment0"))


func test_request_head_and_tail_type_validate_and_replicate() -> void:
	var models := _feature as PlayerModels
	models.request_head_type("frog")
	assert_eq(models.type_for_head(1), "frog")
	models.request_head_type("nonsense")
	assert_eq(models.type_for_head(1), "frog", "Invalid values are ignored")
	models.request_head_type("human")
	assert_eq(models.type_for_head(1), "human")
	models.request_tail_type("fin")
	assert_eq(models.type_for_tail(1), "fin")
	models.request_tail_type("nonsense")
	assert_eq(models.type_for_tail(1), "fin", "Invalid values are ignored")
	models.request_tail_type("none")
	assert_eq(models.type_for_tail(1), "none")


func test_new_players_spawn_with_their_already_requested_head_and_tail_types() -> void:
	var models := _feature as PlayerModels
	var remote := PLAYER_SCENE.instantiate() as Player
	remote.name = "11"
	remote.set_multiplayer_authority(11)
	add_child_autofree(remote)
	models.head_types = {11: "bird"}
	models.tail_types = {11: "fluffy"}
	_feature._process(0.0)
	var other := remote.get_node("Body/Avatar") as BlockPlayerModel
	assert_eq(other.head_type, &"bird")
	assert_eq(other.tail_type, &"fluffy")
	assert_eq(_model.head_type, &"human", "Peer 1's own choice is unaffected")
	assert_eq(_model.tail_type, &"none", "Peer 1's own choice is unaffected")
