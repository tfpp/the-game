extends RefCounted
# gdlint: disable=max-returns
# Command dispatch uses early returns to keep validation next to each command.
## Explicit adapter to existing settings owners. Never evaluates code or arbitrary properties.

const GitCommands := preload("res://features/console/git_commands.gd")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const HELP := {
	"git": "Read-only repository snapshot; git help lists supported commands",
	"help": "List commands; help <text> filters them",
	"clear": "Clear console output",
	"sensitivity": "Mouse sensitivity: 0.1..10 (local, saved)",
	"stick_scale": "Controller look scale: 0.25..3 (local, saved)",
	"touch_scale": "Touch look scale: 0.25..3 (local, saved)",
	"scheme": "left | right (local, saved)",
	"volume": "Overall volume: 0..1 (local, saved)",
	"effects_volume": "Sound effects: 0..1 (local, saved)",
	"mute": "0 | 1 (local, saved)",
	"jump_height_scale": "0.5..2.5 (shared world)",
	"frog_hop_rate": "0.4..3 (shared world)",
	"frog_jump_height_scale": "0.5..4 (shared world)",
	"sv_cheats": "0 | 1 (shared world; enables noclip access)",
	"noclip": "Toggle flight; requires sv_cheats 1",
	"bind": "bind <action> <key name | mouse:1..9 | pad:0..20>; saved locally",
	"reset_bindings": "Reset all bindings to the current handedness preset",
}

var tree: SceneTree
var git_commands := GitCommands.new()


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree


func execute(raw: String) -> String:
	var words := raw.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var command := words[0].to_lower()
	var value := " ".join(words.slice(1))
	if not HELP.has(command):
		return "Unknown command. Type help or use Tab to complete."
	if command == "help":
		var lines: PackedStringArray = []
		for key: String in HELP:
			if value.is_empty() or key.contains(value.to_lower()):
				lines.append("%s — %s" % [key, HELP[key]])
		return "\n".join(lines)
	if command == "git":
		return git_commands.execute(value)
	if command == "clear":
		return ""
	if command == "bind":
		return _bind(words)
	var controls := _page("Controls")
	if command == "reset_bindings":
		if controls != null and value.is_empty():
			controls.reset_bindings()
			return "Bindings reset."
		return HELP[command]
	if command == "scheme":
		if value.is_empty():
			return "scheme %s" % ("left" if Controls.scheme == 0 else "right")
		if value not in ["left", "right"] or controls == null:
			return HELP[command]
		controls.set_scheme(0 if value == "left" else 1)
		return "scheme " + value
	var noclip := tree.get_first_node_in_group(&"noclip")
	if command == "noclip":
		return str(noclip.toggle()) if noclip != null and value.is_empty() else HELP[command]
	if value.is_empty():
		return "%s = %s — %s" % [command, _current(command), HELP[command]]
	if not value.is_valid_float() or not is_finite(value.to_float()):
		return "Expected a finite number. " + str(HELP[command])
	var number := value.to_float()
	if command in ["mute", "sv_cheats"] and value not in ["0", "1"]:
		return "Expected 0 or 1."
	match command:
		"sensitivity", "stick_scale", "touch_scale":
			if controls == null:
				return "Controls unavailable."
			var method: String = {
				"sensitivity": "set_mouse_sensitivity",
				"stick_scale": "set_stick_scale",
				"touch_scale": "set_touch_scale"
			}[command]
			controls.call(method, number)
		"volume", "effects_volume", "mute":
			var audio := _page("Audio")
			if audio == null:
				return "Audio unavailable."
			if command == "mute":
				audio.set_muted(value == "1")
			else:
				audio.set_volume("master" if command == "volume" else "effects", number)
		"sv_cheats":
			if noclip == null:
				return "Noclip unavailable."
			noclip.request_cheats.rpc_id(1, int(number))
			return "Requested sv_cheats %s; query sv_cheats for server state." % value
		_:
			var game := _page("Game")
			if game == null:
				return "Game settings unavailable."
			game.rpc_id(1, "request_" + command, number)
			return "Requested %s %s (shared world)." % [command, value]
	return "%s = %s" % [command, _current(command)]


func suggestions(raw: String) -> PackedStringArray:
	var query := raw.to_lower().strip_edges(true, false)
	var candidates: Array[String] = []
	if query.begins_with("git "):
		candidates.assign(GitCommands.COMMANDS)
	elif query.begins_with("bind "):
		var words := query.split(" ", false)
		if (
			words.size() >= 2
			and Bindings.actions().has(StringName(words[1]))
			and query.count(" ") >= 2
		):
			for key: String in [
				"Space",
				"Shift",
				"Ctrl",
				"Alt",
				"Enter",
				"Tab",
				"F1",
				"F2",
				"F3",
				"Up",
				"Down",
				"Left",
				"Right",
				"QuoteLeft"
			]:
				candidates.append("bind " + words[1] + " " + key.to_lower())
			for code: int in range(KEY_A, KEY_Z + 1):
				candidates.append("bind " + words[1] + " " + char(code).to_lower())
			for code: int in range(21):
				candidates.append("bind " + words[1] + " pad:" + str(code))
			for code: int in range(1, 10):
				candidates.append("bind " + words[1] + " mouse:" + str(code))
		else:
			for action: StringName in Bindings.actions():
				candidates.append("bind " + str(action) + " ")
	elif query.contains(" "):
		var command := query.get_slice(" ", 0)
		var values: Array = []
		if command in ["sv_cheats", "mute"]:
			values = ["0", "1"]
		elif command == "scheme":
			values = ["left", "right"]
		for value: String in values:
			candidates.append(command + " " + value)
	else:
		for command: String in HELP:
			candidates.append(command)
	candidates.sort()
	var prefix: PackedStringArray = []
	var partial: PackedStringArray = []
	for candidate: String in candidates:
		if candidate.to_lower().begins_with(query):
			prefix.append(candidate)
		elif not query.is_empty() and candidate.to_lower().contains(query):
			partial.append(candidate)
	prefix.append_array(partial)
	return prefix


func describe(command: String) -> String:
	return str(HELP.get(command.get_slice(" ", 0), ""))


func _page(label: String) -> Node:
	for node: Node in tree.get_nodes_in_group(&"settings_pages"):
		if node.settings_page_label() == label:
			return node
	return null


func _current(command: String) -> Variant:
	match command:
		"sensitivity":
			return Controls.sensitivity
		"stick_scale":
			return Controls.stick_sensitivity / Controls.STICK_SENSITIVITY
		"touch_scale":
			return Controls.touch_sensitivity / Controls.TOUCH_SENSITIVITY
		"volume", "effects_volume", "mute":
			var audio := _page("Audio")
			if audio != null:
				return (
					int(audio.muted)
					if command == "mute"
					else audio.volumes.get("master" if command == "volume" else "effects", 1.0)
				)
		"sv_cheats":
			var noclip := tree.get_first_node_in_group(&"noclip")
			if noclip != null:
				return int(noclip.cheats_enabled)
		_:
			var game := _page("Game")
			if game != null:
				return game.get(command)
	return "unavailable"


func _bind(words: PackedStringArray) -> String:
	if words.size() < 2 or not Bindings.actions().has(StringName(words[1])):
		return str(HELP["bind"])
	var action := StringName(words[1])
	if words.size() == 2:
		return (
			"%s: %s / %s"
			% [action, Bindings.slot_text(action, false), Bindings.slot_text(action, true)]
		)
	var value := " ".join(words.slice(2)).to_lower()
	var event: InputEvent
	if value.begins_with("mouse:") or value.begins_with("pad:"):
		var raw := value.get_slice(":", 1)
		var pad := value.begins_with("pad:")
		if not raw.is_valid_int() or int(raw) < (0 if pad else 1) or int(raw) > (20 if pad else 9):
			return str(HELP["bind"])
		event = Bindings.from_data({"pad" if pad else "mouse": int(raw)})
	else:
		var code := OS.find_keycode_from_string(value)
		if code == KEY_NONE or code == KEY_ESCAPE:
			return "Unknown or reserved key. Example: bind jump Space"
		event = Bindings.from_data({"key": code})
	var controls := _page("Controls")
	if controls == null:
		return "Controls unavailable."
	controls.rebind(action, event is InputEventJoypadButton, event)
	var clashes := Bindings.conflicts(action, event is InputEventJoypadButton)
	return (
		"Bound %s to %s.%s"
		% [action, value, " Shared with: " + str(clashes) if not clashes.is_empty() else ""]
	)
