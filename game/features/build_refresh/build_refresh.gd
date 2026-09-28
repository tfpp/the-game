extends Node
## Keeps the web client on the canonical build: the one the server runs.
##
## `Network` already rejects a join whose build doesn't match the server's and reports
## the server's build in `server_version_mismatch` (core/net/network.gd); until now the
## player had to notice and click "Reload page" by hand, and the login screen's silent
## reconnect (`ui/login/login_screen.gd`) just kept retrying with the same stale build
## in the meantime. This does the reload for them, the moment a join fails on a version
## mismatch, so every reconnect attempt (the first join, or a dropped-connection retry)
## doubles as a poll for a newer build.
##
## A plain reload keeps the page's URL and leaves localStorage alone, so the session
## token there (`core/net/account_api.gd`) survives and the returning player's client
## signs back in and rejoins on its own instead of losing their place.


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	Network.connection_failed.connect(_on_connection_failed)


func _on_connection_failed(_reason: String) -> void:
	if should_refresh(Network.server_version_mismatch):
		JavaScriptBridge.eval("window.location.reload()")


## True once the server has told us our build is stale (a non-empty
## Network.server_version_mismatch; see core/net/network.gd).
static func should_refresh(server_version_mismatch: String) -> bool:
	return not server_version_mismatch.is_empty()
