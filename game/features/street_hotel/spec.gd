extends RefCounted
## Shared dimensions for exterior, sockets, streaming, controls and window views.

const FLOORS := 10
const ROOMS_PER_FLOOR := 20
const STOREY := 4.2
const HEIGHT := 3.3
const LENGTH := 72.0
const WIDTH := 19.0
const LIFT_CENTER := Vector3(6, 0, 4)
const SHAFT_X0 := 4.0
const SHAFT_X1 := 8.0
const SHAFT_Z0 := 2.2
const SHAFT_Z1 := 5.5
const STREET_ORIGIN := Vector3(-44.5, 0, -8)
const INTERIOR_ORIGIN := Vector3(0, 0, -2500)
const THEMES: Array[String] = [
	"Reception & Burgundy",
	"Sage Garden",
	"Amber Lounge",
	"Blue Hour",
	"Rosewood",
	"Olive Reading",
	"Copper Sunset",
	"Ivory Gallery",
	"Midnight Teal",
	"Crown Penthouse",
]
const COLORS: Array[Color] = [
	Color("743b35"),
	Color("65705b"),
	Color("90714c"),
	Color("52697e"),
	Color("794c52"),
	Color("747348"),
	Color("8b5b40"),
	Color("aaa084"),
	Color("3f6768"),
	Color("8e754a"),
]


static func room_number(floor_index: int, room_index: int) -> int:
	return (floor_index + 1) * 100 + room_index + 1


static func recipe(floor_index: int, room_index: int) -> Dictionary:
	var seed := floor_index * 137 + room_index * 31
	return {
		"number": room_number(floor_index, room_index),
		"seed": seed,
		"layout": seed % 5,
		"twin": room_index % 4 == 0,
		"bed_z": 3.7 + (seed % 4) * .35,
		"desk_z": 6.5 - (seed % 3) * .4,
		"accent": COLORS[floor_index].lerp(Color("c6b493"), (room_index % 5) * .07),
		"decor": seed % 7,
		"theme": THEMES[floor_index]
	}
