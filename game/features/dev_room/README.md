# Dev room

One sealed room holds the existing warp doors. The casino booth is removed;
open chat with Enter and type `!warp dev`. `!warp` lists destinations:
`dev`, `casino`, `lounge`, `cellar`, `hotel`, `apartments`, `props`, `garage`, `street`.
`/warp <name>` also works. The return door lands on the clear north promenade.
Commands are private (not public chat/Discord), server-validated and limited to
one successful warp per second per player. They move only the requester and finish
any active slum run, just like ordinary return doors. No arbitrary paths or coordinates
are accepted. Streamed interiors preload on the owner before teleporting.

The Gun-O-Matic and its trash can stand on the east wall at (313, 0, -300)
and (313, 0, -298.2), respectively, owned by `features/gun_machine`. Use the
same E / B or Circle / touch USE controls; random guns still cost $20.
The kiosk clears the warp-door paths and the room arrival/return route.

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
player; there is no new networking or state. The room remains a closed-off GPS area
(**Dev Room**); its hint explains `!warp dev` rather than routing through a removed booth. To add another warp door, place it on a free wall slot (the
east/west walls) and point its return door at a marker in front of it.

`tests/features/dev_room/` checks command/return round trips, validation, and that every warp door sits
inside the room and that each return marker lands inside it.

The Street District, Hotel Props and procedural garage teleporters here are hidden
and locked until `sv_cheats 1` ([dev access](../dev_access/README.md)). The same restriction applies to `!warp street`, `!warp props` and `!warp garage`.
Dev, casino, lounge, cellar, hotel and apartment commands stay open for normal play.
`warp_commands.gd` extends the authenticated chat command group instead of adding a
second request RPC; NetworkedEntity supplies authority-only preload events and Player
retains its existing owner-only teleport and movement replication.
