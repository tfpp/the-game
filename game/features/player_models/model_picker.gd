extends Node
## Character settings page. Uses the existing rig, clothing and SettingsStore.

const ROWS: Array[Dictionary] = [
	{
		"id": "body",
		"label": "Body",
		"options":
		[
			{"id": "default", "label": "Default"},
			{"id": "girl", "label": "Girl"},
			{"id": "penguin", "label": "Penguin"},
		],
	},
	{
		"id": "head",
		"label": "Head",
		"options":
		[
			{"id": "human", "label": "Human"},
			{"id": "frog", "label": "Frog"},
			{"id": "bird", "label": "Bird"},
		],
	},
	{
		"id": "tail",
		"label": "Tail",
		"options":
		[
			{"id": "none", "label": "None"},
			{"id": "lizard", "label": "Lizard"},
			{"id": "fin", "label": "Fin"},
			{"id": "fluffy", "label": "Fluffy"},
		],
	},
]

var _preview: InventoryPreview
var _choices: Dictionary = {}
var _saved: Dictionary = {}
var _pending: Array[Dictionary] = []
var _restore := true


func _ready() -> void:
	add_to_group(&"settings_pages")
	_saved = SettingsStore.load_data("character")
	if not PlayerAppearance.valid(_saved):
		_saved = {}
	Network.mode_changed.connect(_on_mode_changed)
	var models := get_parent() as PlayerModels
	(models.get_node("NetworkedEntity") as NetworkedEntity).request_finished.connect(_finished)


func _process(_delta: float) -> void:
	var models := get_parent() as PlayerModels
	if _restore and Network.mode != Network.Mode.SERVER and multiplayer.multiplayer_peer != null:
		if (
			(
				multiplayer.multiplayer_peer.get_connection_status()
				== MultiplayerPeer.CONNECTION_CONNECTED
			)
			and _local_player_exists()
		):
			_restore = false
			if not _saved.is_empty():
				_pending.append(_saved.duplicate())
				models.entity.request_action(&"appearance", _saved)
	if is_instance_valid(_preview) and _preview.is_visible_in_tree():
		_refresh()


func _local_player_exists() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node.get_multiplayer_authority() == multiplayer.get_unique_id():
			return true
	return false


func settings_page_label() -> String:
	return "Character Model"


func settings_page_build() -> Control:
	_choices.clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var status := Label.new()
	status.text = "Your look, shared with everyone. Drag the preview to turn."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_preview = InventoryPreview.new()
	box.add_child(_preview)
	_preview.ready.connect(func() -> void: _preview.mouse_filter = Control.MOUSE_FILTER_STOP)
	_preview.gui_input.connect(_turn_preview)
	for row: Dictionary in ROWS:
		var values: Array[String] = []
		var labels: Array[String] = []
		for option: Dictionary in row["options"]:
			values.append(option["id"])
			labels.append(option["label"])
		_add_choice(box, row["id"], row["label"], labels, values)
	_add_choice(
		box,
		"skin",
		"Skin tone",
		["Automatic", "Porcelain", "Light", "Warm", "Tan", "Brown", "Deep brown", "Dark", "Deep"],
		[]
	)
	_add_choice(
		box,
		"hair",
		"Hairstyle",
		["Classic", "Cropped", "Side swept", "Long", "Bald"],
		PlayerAppearance.HAIR_STYLES
	)
	_add_choice(
		box, "hair_color", "Hair color", ["Dark brown", "Brown", "Blond", "Auburn", "Silver"], []
	)
	_add_choice(box, "outfit", "Outfit", ["Casual", "Tactical"], PlayerAppearance.OUTFITS)
	_add_choice(box, "eyes", "Eye color", ["Brown", "Blue", "Green", "Grey"], [])
	var note := Label.new()
	note.text = (
		"Skin, hair, eye and outfit choices are saved on this device. "
		+ "Clothing is equipped in your backpack. Human details appear on human heads."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	_refresh.call_deferred()
	return box


func _add_choice(
	box: VBoxContainer, key: String, label: String, labels: Array[String], values: Array[String]
) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var title := Label.new()
	title.text = label
	title.custom_minimum_size.x = 130
	row.add_child(title)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = 38
	for text: String in labels:
		choice.add_item(text)
	choice.item_selected.connect(_select.bind(key, values))
	row.add_child(choice)
	_choices[key] = choice


func _select(index: int, key: String, values: Array[String]) -> void:
	if not _can_customize():
		return
	var models := get_parent() as PlayerModels
	if key in ["body", "head", "tail"]:
		models.entity.request_action(StringName(key), {"value": values[index]})
		return
	var appearance: Dictionary = (
		_pending.back().duplicate()
		if not _pending.is_empty()
		else models.appearance_for(multiplayer.get_unique_id())
	)
	appearance[key] = (
		values[index] if not values.is_empty() else (index - 1 if key == "skin" else index)
	)
	_pending.append(appearance.duplicate())
	models.entity.request_action(&"appearance", appearance)


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action != &"appearance" or _pending.is_empty():
		return
	var data: Dictionary = _pending.pop_front()
	if result == NetworkedEntity.Result.ACCEPTED:
		_saved = data
		SettingsStore.save_data("character", data)


func _refresh() -> void:
	if not is_instance_valid(_preview):
		return
	var models := get_parent() as PlayerModels
	var peer := multiplayer.get_unique_id()
	var appearance := models.appearance_for(peer)
	for choice: OptionButton in _choices.values():
		choice.disabled = not _can_customize()
	var types := {
		"body": models.type_for(peer),
		"head": models.type_for_head(peer),
		"tail": models.type_for_tail(peer)
	}
	for row: Dictionary in ROWS:
		for index: int in row["options"].size():
			if row["options"][index]["id"] == types[row["id"]]:
				(_choices[row["id"]] as OptionButton).select(index)
	(_choices["skin"] as OptionButton).select(int(appearance["skin"]) + 1)
	(_choices["hair"] as OptionButton).select(PlayerAppearance.HAIR_STYLES.find(appearance["hair"]))
	(_choices["hair_color"] as OptionButton).select(int(appearance["hair_color"]))
	(_choices["outfit"] as OptionButton).select(
		PlayerAppearance.OUTFITS.find(str(appearance.get("outfit", "casual")))
	)
	(_choices["eyes"] as OptionButton).select(int(appearance["eyes"]))
	_preview.model.set_body_type(types["body"])
	_preview.model.set_head_type(types["head"])
	_preview.model.set_tail_type(types["tail"])
	var hand := Hand.for_peer(get_tree(), peer)
	_preview.model.set_skin_index(
		hand.skin_tone_index() if hand != null else PlayerSkin.index_for_id(peer)
	)
	_preview.model.set_appearance(appearance)
	_preview.show_clothing(
		hand.inventory().shirt if hand != null else "",
		hand.inventory().pants if hand != null else ""
	)


func _turn_preview(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_preview.model.rotation.y += event.relative.x * 0.012
	elif event is InputEventScreenDrag:
		_preview.model.rotation.y += event.relative.x * 0.012


func _on_mode_changed(_mode: Network.Mode) -> void:
	_restore = true
	_pending.clear()


func _can_customize() -> bool:
	return (
		multiplayer.multiplayer_peer != null
		and (
			multiplayer.multiplayer_peer.get_connection_status()
			== MultiplayerPeer.CONNECTION_CONNECTED
		)
		and (multiplayer.is_server() or multiplayer.get_peers().has(1))
	)
