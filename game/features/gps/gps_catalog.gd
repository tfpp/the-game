class_name GpsCatalog
extends Node
## Local adapters over existing replicated entities. Never writes to their state.
## Penguin labels come from the penguin's own `display_name` (husband vs wife).

var _markers: Dictionary[int, GpsDestination] = {}


func refresh() -> void:
	var seen: Dictionary[int, bool] = {}
	for group: StringName in [&"players", &"killable", &"interactables"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not node is Node3D or node.is_in_group(&"local_player"):
				continue
			var id := node.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not _markers.has(id):
				var marker := GpsDestination.new()
				marker.source = node
				marker.tracks_source = true
				marker.category = category_for(node)
				add_child(marker)
				_markers[id] = marker
			_markers[id].label = label_for(node)
			_markers[id].hint = _markers[id].category
	for id: int in _markers.keys():
		if not seen.has(id):
			_markers[id].free()
			_markers.erase(id)


static func category_for(node: Node) -> String:
	if node is Frog or node is Penguin or node is Bird:
		return "Animals"
	if (
		node is Player
		or node is CasinoPatron
		or node is StationaryPatron
		or node is Vivienne
		or node is Celeste
		or node is Gnome
		or node.name == &"Bartender"
	):
		return "People"
	return "Objects"


static func label_for(node: Node) -> String:
	if node is ItemPickup or node is ThrownItem:
		var definition := ItemCatalog.find(str(node.get("item_id")))
		if definition != null:
			return definition.display_name
	if node is GarageDoor:
		return (node as GarageDoor).door_label
	if node is LootFence:
		return "Pawn shop counter"
	if node is KebabShop:
		return "İstanbul Kebab counter"
	if node is LootContainer:
		return (node as LootContainer).noun.capitalize()
	if node is SlotMachine:
		return "Slot machine — %s" % node.name
	if node is WallGun:
		return "%s (pawn shop wall)" % ItemCatalog.find((node as WallGun).item_id).display_name
	if node is GunMachineKiosk:
		return "Gun machine"
	if node is SoccerBall:
		return "Soccer ball"
	if node is RouletteTable:
		return "Roulette table"
	if node is KaabaPrayer:
		return "Kaaba"
	if node is Player:
		var player := node as Player
		return player.display_name if player.display_name != "" else "Player %s" % player.name
	if node is CasinoPatron:
		match (node as CasinoPatron).look:
			PatronModel.MAMDANI_LOOK:
				return "Zohran Mamdani"
			PatronModel.TRUMP_LOOK:
				return "Donald Trump"
			PatronModel.MITCH_LOOK:
				return "Mitch McConnell and intern"
		return "Casino patron %d" % ((node as CasinoPatron).look + 1)
	if node is Vivienne:
		return "Vivienne"
	if node is Celeste:
		return "Celeste"
	if node is Penguin:
		return (node as Penguin).display_name
	if node is Bird:
		return "Bird"
	if node is Gnome:
		return "%s gnome %d" % [node.get_parent().name, (node as Gnome).index + 1]
	return str(node.name).to_snake_case().capitalize()
