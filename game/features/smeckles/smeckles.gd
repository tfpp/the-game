class_name Smeckles
extends Node3D
## Smeckles: a lighthearted currency players collect from pickups scattered around
## the map. Balances are server-authoritative and replicated to every peer (see the
## `Sync` synchronizer) so each client's HUD can read its own total without asking.

## peer_id (as String, since Dictionary keys round-trip through replication that way) -> int
@export var balances: Dictionary = {}


func balance_for(peer_id: int) -> int:
	return int(balances.get(str(peer_id), 0))


## Server-only: credits `peer_id` with `amount` Smeckles. Reassigns the whole
## dictionary rather than mutating in place, the same way `SlotMachine.state` does,
## since the synchronizer only notices a new value, not an in-place edit.
func grant(peer_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var next := balances.duplicate()
	var key := str(peer_id)
	next[key] = int(next.get(key, 0)) + amount
	balances = next
