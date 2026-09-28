class_name SettingsStore
extends RefCounted
## Small persistent JSON store for local, per-install preferences, mirroring
## `AccountApi.load_value`/`save_value`: localStorage on the web (key
## `the-game.<name>`), a ConfigFile natively (`user://<name>.cfg`).

const WEB_PREFIX := "the-game."
const SECTION := "settings"
const KEY := "state"


## The saved Dictionary for `name`, or an empty one if nothing (valid) is saved.
static func load_data(name: String) -> Dictionary:
	var text := load_text(name)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return parsed as Dictionary if parsed is Dictionary else {}


static func save_data(name: String, data: Dictionary) -> void:
	save_text(name, JSON.stringify(data))


static func load_text(name: String) -> String:
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval(
			"window.localStorage.getItem(%s) || ''" % JSON.stringify(WEB_PREFIX + name)
		)
		return str(value) if value != null else ""
	var config := ConfigFile.new()
	if config.load(native_path(name)) != OK:
		return ""
	return str(config.get_value(SECTION, KEY, ""))


static func save_text(name: String, value: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			(
				"window.localStorage.setItem(%s, %s)"
				% [JSON.stringify(WEB_PREFIX + name), JSON.stringify(value)]
			)
		)
		return
	var config := ConfigFile.new()
	config.load(native_path(name))
	config.set_value(SECTION, KEY, value)
	config.save(native_path(name))


static func native_path(name: String) -> String:
	return "user://%s.cfg" % name
