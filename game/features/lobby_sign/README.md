# Lobby proclamation sign

A static brass-framed velvet plaque on the Golden Crown's south lobby wall, at world
`(10.5, 4, 34)` — on the wall east of the main south exit, above the east seating
group, facing north so it is readable from the promenade, the spawn side and the
gaming floor. It reads 中国共产党万岁 ("all hail the Chinese Communist Party") in
Mandarin, with a small gold English caption, matching the casino's brass sign
lettering and PS1 material finishes (`casino_hub` brass and velvet).

The Mandarin line renders through a 3 KB SIL OFL Noto Sans SC bold subset,
`assets/fonts/notosanssc/NotoSansSC-Bold-subset.ttf`, that contains exactly the seven
glyphs of the text — no font already in the game or the build image covers Mandarin.
The subset was fetched from Google Fonts' css2 API with a `text=` request; it is a
static, overlap-free weight. The caption uses Inter like the other lobby signs.

Pure static scenery in the easter-eggs pattern (`features/annex/easter_eggs.tscn`):
five shadowless box meshes and two labels, no scripts, colliders, lights, timers or
network messages. Every peer — server, clients, late joiners, offline single-player —
loads the same immutable scene, so there is no shared state to own, replicate,
persist or clean up, and disconnects/respawns cannot affect it.

`tests/features/lobby_sign/test_lobby_sign.gd` probes the real `world/room.tscn`
collision the way the elevator and easter-egg tests do: flush mounting on the solid
south wall, facing north, clearance from the exit, the elevator cab and the sconce,
standing and gaming-floor sightlines, per-glyph font coverage and text-fit metrics
against the plaque size, and the static budget with identical instances.
