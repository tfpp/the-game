extends RefCounted
## Temporary local animation switches. No persistence, RPCs or per-frame tree scans.

const GROUPS := ["guests", "dealers", "musicians", "patrons", "players"]
const USAGE := "profile_animations [all|guests|dealers|musicians|patrons|players] [0|1]"

static var guests := true
static var dealers := true
static var musicians := true
static var patrons := true
static var players := true
static var fingers := true
static var skeleton := true


static func reset() -> void:
	set_group("all", true)
	fingers = true
	skeleton = true


static func execute_fingers(value: String) -> String:
	if not value.is_empty():
		if value not in ["0", "1"]:
			return "profile_fingers [0|1]"
		fingers = value == "1"
	return "profile_fingers %d (local; 0 = frozen, 1 = animated)" % int(fingers)


static func execute_skeleton(value: String) -> String:
	if not value.is_empty():
		if value not in ["0", "1"]:
			return "profile_skeleton [0|1]"
		skeleton = value == "1"
	return "profile_skeleton %d (local; 0 = main bone pose frozen, 1 = animated)" % int(skeleton)


static func set_group(group: String, enabled: bool) -> void:
	if group == "all":
		for name: String in GROUPS:
			set_group(name, enabled)
		return
	match group:
		"guests":
			guests = enabled
		"dealers":
			dealers = enabled
		"musicians":
			musicians = enabled
		"patrons":
			patrons = enabled
		"players":
			players = enabled


static func execute(value: String) -> String:
	var words := value.to_lower().split(" ", false)
	if words.size() > 2:
		return USAGE
	var group := "all" if words.is_empty() else words[0]
	if group != "all" and group not in GROUPS:
		return USAGE
	if words.size() == 2:
		if words[1] not in ["0", "1"]:
			return USAGE
		set_group(group, words[1] == "1")
	var states := {
		"guests": guests,
		"dealers": dealers,
		"musicians": musicians,
		"patrons": patrons,
		"players": players,
	}
	var lines: PackedStringArray = []
	for name: String in GROUPS:
		if group == "all" or name == group:
			lines.append("profile_animations %s %d" % [name, int(states[name])])
	return "Local animation switches (0 = frozen, 1 = animated):\n" + "\n".join(lines)
