# Dev room

One sealed room that holds every warp door, so the casino floor stays tidy. The
casino's north promenade has a single **DEV ROOM** booth at world `(12, 0, -18.4)`; press
Use (E, controller B/Circle or touch Use) on its door to arrive in the room at
`(300, 0, -300)`. The **BACK TO THE CASINO** door on the south wall returns you to
the booth.

Warp doors in the room (each still belongs to its own feature, which also owns its
return marker):

| Wall | Door | Feature |
| --- | --- | --- |
| South, x 290 | Lily Apartments | `apartments/` (`Entrance`, `CasinoArrival`) |
| South, x 295 | Lounge booth | `room_doors/` (`Lobby`) |
| South, x 300 | Back to the casino | this feature (`Room/ReturnDoor`) |
| South, x 306 | Hotel wing | `hotel_annex/` (`EntranceModel`, `Entrance`, `CasinoArrival`) |
| South, x 311 | Hotel Props | `hotel_props/` (`Entrance`, `CasinoArrival`) |
| North, x 294 | Procedural garage teleporter | `procedural_rooms/` (`Entrance`, `CasinoArrival`) |
| North, x 306 | Shooting gallery arch | `shooting_gallery/` (`Entrance`, `Arena/Exit`) |

Each feature's "return to the casino" door now lands in front of its door here.
The doors are ordinary `GarageDoor`s, so the server validates range and moves the
player; there is no new networking or state. The room is a closed-off GPS area
(**Dev Room**), so GPS routes to the lounge, hotel and other rooms go through the
booth. To add another warp door, place it on a free wall slot (the
east/west walls) and point its return door at a marker in front of it.

`tests/features/dev_room/` checks the booth round trip, that every warp door sits
inside the room and that each return marker lands inside it.
