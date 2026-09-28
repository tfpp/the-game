class_name PlayerSkin
extends RefCounted
## A stable ID-to-palette mapping. Account IDs stay on the server; only the
## resulting palette index is included in Hand spawn data for other clients.

const TONES: Array[Color] = [
	Color("f1d0b5"),
	Color("dfb18b"),
	Color("ca946d"),
	Color("b57750"),
	Color("965f3f"),
	Color("77472f"),
	Color("593725"),
	Color("40291e"),
]


static func index_for_id(player_id: int) -> int:
	return posmod(player_id, TONES.size())
