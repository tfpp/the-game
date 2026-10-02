extends Node3D
## Static task endpoints exist on every peer; only the shift snapshot changes.

var kind := 0  # 0 counter, 1 dirty glass, 2 seated patron
var index := -1
var talk: NetworkedInteraction
var _label: Label3D
var _glass: Node3D
var _shift: BusboyShift


func _ready() -> void:
	_shift = get_parent() as BusboyShift
	add_to_group(&"interactables")
	talk = NetworkedInteraction.new()
	talk.name = "NetworkedEntity"
	talk.interaction_range = 2.2
	add_child(talk)
	talk.register_use(can_use, _apply, 0.2)
	_label = Label3D.new()
	_label.name = "Label"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 24
	_label.outline_size = 6
	_label.pixel_size = 0.003
	_label.modulate = Color("ead6a4")
	_label.position.y = 0.4 if kind != 2 else 1.1
	add_child(_label)
	if kind != 2:
		_glass = BusboyShift.glass_view()
		add_child(_glass)
	present(_shift.snapshot)


func can_use(player: Player) -> bool:
	return talk.in_range(player) and _shift.eligible(player, kind, index)


# gdlint: disable=max-returns
func interaction_text() -> String:
	var state := _shift.snapshot
	if kind == 1:
		return "Busboy — pick up empty glass"
	if kind == 2:
		return "Deliver drink to table %d" % (index + 1)
	var phase := str(state.get("phase", "idle"))
	if phase in ["idle", "failed", "paid"]:
		return "Start busboy shift — 2 minutes / $10 prize"
	if phase == "prize":
		return "Collect busboy prize — $10 (Use again if wallet busy)"
	var held := int(state.get("cargo", -1))
	if held == -2:
		return "Drop off empty glass"
	if held >= 0:
		return "Deliver this drink to table %d" % (held + 1)
	return (
		"Take a patron's drink"
		if not (state.get("orders", {}) as Dictionary).is_empty()
		else ("Busboy — collect empty glasses from tables")
	)


func use() -> void:
	talk.request_use()


func _apply(player: Player) -> bool:
	return _shift.act(player, kind, index)


func present(state: Dictionary) -> void:
	var phase := str(state.get("phase", "idle"))
	if kind == 0:
		var caption := "BUSBOY SHIFT\nUse to work 2 minutes for $10\nOne glass at a time"
		if phase == "active":
			var held := int(state.get("cargo", -1))
			var cargo := "Empty hands"
			if held == -2:
				cargo = "Return empty glass here"
			elif held >= 0:
				cargo = "Drink → table %d" % (held + 1)
			caption = (
				"BUSBOY — %ds left\nDirty: %d / 8 • Orders: %d\n%s\n9 dirty / 35s late = no prize"
				% [
					int(state.get("left", 0)),
					(state.get("dirty", []) as Array).size(),
					(state.get("orders", {}) as Dictionary).size(),
					cargo
				]
			)
		elif phase == "failed":
			caption = "SHIFT FAILED — no prize\nUse to try again"
		elif phase == "prize":
			caption = "SHIFT COMPLETE!\nWorker: Use to collect $10"
		elif phase == "paid":
			caption = "$10 prize paid!\nUse to start another shift"
		_label.text = caption
	elif kind == 1:
		visible = phase == "active" and index in (state.get("dirty", []) as Array)
		_label.text = "EMPTY"
		_label.visible = true
		for other: int in state.get("dirty", []) as Array:
			if other >= index - index % 3 and other < index:
				_label.visible = false
	else:
		var orders: Dictionary = state.get("orders", {})
		visible = phase == "active" and orders.has(index)
		_label.text = (
			"Table %d: drink please!\n%ds left" % [index + 1, ceili(float(orders.get(index, 0)))]
		)
