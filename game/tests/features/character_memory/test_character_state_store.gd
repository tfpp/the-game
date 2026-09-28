extends GutTest
## Pure logic for character_memory (features/character_memory/character_state_store.gd).

var _store: CharacterStateStore


func before_each() -> void:
	_store = CharacterStateStore.new()


func test_unknown_key_has_no_position() -> void:
	assert_false(_store.has_position("alice"))
	assert_eq(_store.get_position("alice"), Vector3.ZERO)


func test_set_then_get_round_trips() -> void:
	_store.set_position("alice", Vector3(1, 2, 3))
	assert_true(_store.has_position("alice"))
	assert_eq(_store.get_position("alice"), Vector3(1, 2, 3))


func test_normalize_key_trims_and_lowercases() -> void:
	assert_eq(CharacterStateStore.normalize_key("  Alice "), "alice")


func test_json_round_trip() -> void:
	_store.set_position("alice", Vector3(1, 2, 3))
	_store.set_position("bob", Vector3(-4, 5.5, 6))
	var restored := CharacterStateStore.new()
	restored.from_json(_store.to_json())
	assert_eq(restored.get_position("alice"), Vector3(1, 2, 3))
	assert_eq(restored.get_position("bob"), Vector3(-4, 5.5, 6))


func test_loading_malformed_json_leaves_store_empty() -> void:
	_store.set_position("alice", Vector3(1, 2, 3))
	_store.from_json("not json")
	assert_false(_store.has_position("alice"))
	assert_engine_error_count(1, "JSON.parse_string logs the malformed input itself")


func test_loading_skips_entries_missing_coordinates() -> void:
	_store.from_json(JSON.stringify({"alice": {"x": 1, "y": 2}}))
	assert_false(_store.has_position("alice"))
