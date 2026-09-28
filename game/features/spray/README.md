# Spray

Press `T` (rebindable) to spray a decal on the surface you're looking at, up to 6 m away.
The client raycasts and calls `request_spray` on the server, which checks the spot is near
the sender's player, rate-limits to one spray per second per player, and broadcasts
`place_spray` to everyone. The newest 60 sprays are kept.

The default spray is a placeholder red "!" drawn in code (`Spray._default_texture`); the
requested meme image couldn't be fetched in CI, so swap it for a real texture there.
