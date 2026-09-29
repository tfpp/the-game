# Casino patrons

Four gamblers in suits who stroll the gaming floor, each on their own loop, pausing
now and then to look around. Punch them with `features/boxing` and
they flinch, stagger back and turn to face you; enough punches (or one full power
punch) knock them out into a limp ragdoll. They get back up 4 s after the last
punch, walk back to where they were hit and carry on. Any weapon gibs them; they
walk back in from the start of their route 6 s later.

## How it works

- `casino_patrons.gd` (feature root) spawns one `patron.tscn` per route through a
  `MultiplayerSpawner` on the server. Spawn data is just the index, so every peer
  builds the same look and route.
- `patron.gd` (`CasinoPatron`, server-simulated): walks the route from
  `patron_math.gd`, waits up to 2 s for a player standing right in front of it,
  then squeezes past (players don't collide with patrons, layer 2 like frogs).
  `take_punch(attacker_peer, strength, direction)` is the boxing contract; the daze,
  ragdoll time and knock-away tuning come from
  `features/shooting_gallery/humanoid_target.gd`, so punches feel the same.
  `take_hit` makes it a `killable` for every gun.
- Replicated: `net_position`, `net_yaw`, `net_alive`, `net_ragdoll`, `net_fall_dir`
  (all on spawn, so late joiners see downed patrons). The flinch and death effects
  are cosmetic RPCs.
- `patron_model.gd` (`PatronModel`): a jointed body (hips, torso, neck, shoulders,
  elbows, legs, knees) posed locally each frame: a walk cycle from the distance
  moved, idle head turns, and a sprawled pose for the ragdoll while the whole body
  topples toward the punch.
- Routes stay on the clear aisles of the gaming floor (y −1.5);
  `tests/features/casino_patrons/test_patron_routes.gd` sweeps every leg against the
  real room, slots and roulette.

Nothing is persisted.

## Stationary characters

`stationary_patron.gd` wraps the existing salon dealer, guest and seated models in
layer-2 hitboxes fitted to their imported poses. Salon guests, dealers, bartender
and the Lily Apartments clerk now implement the same `killable` / `take_hit(peer)`
contract as roaming patrons. A direct hit from any gun kills them; repeated hits
while dead do nothing. They respawn in place after six seconds. Power punches also
use this existing contract. Ordinary jabs do not affect these stationary characters.

Each body owns `net_alive`; its `NetworkedEntity` replicates changes and initial
state for late joiners, and sends the shared cosmetic MeshExplosion death event.
There is no client-callable death action: existing weapons validate firing and the
server resolves collisions. Session changes reset deaths; disconnecting the shooter
does not affect the respawn. The apartment clerk lives outside streamed Content,
so unloading the lobby cannot reset its state or remove its server hitbox. The desk
still allocates apartments during the respawn delay. Existing gun controls apply
(left click or controller right shoulder); no new touch firing control is added.
