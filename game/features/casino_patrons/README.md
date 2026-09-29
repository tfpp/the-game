# Casino patrons

Six patrons in suits stroll the gaming floor: five walk their own loops, pausing
now and then to look around, while Trump follows Mamdani. Punch them with `features/boxing` and
they flinch, stagger back and turn to face you; enough punches (or one full power
punch) knock them out into a limp ragdoll. They get back up 4 s after the last
punch, walk back to where they were hit and carry on. The fifth (`PatronModel.MAMDANI_LOOK`) is Zohran Mamdani, New York
City's mayor, with a trimmed beard, blue tie and a floating name tag; he strolls
an aisle beside the slot machines. He is essential: a gunshot knocks him out for
5 s (`PatronMath.KNOCKOUT_S`) instead of gibbing him, and he gets up where he fell.
Press Use (E) near him to talk: he pays $10 of subway fare through
`PlayerMoney.credit_coin()` once an hour per account (per peer for guests). His
reply shows as a movie-style subtitle (`features/subtitles`) only to the player who talked; the cooldown lives in
server memory and resets on restart. Any weapon gibs ordinary patrons; they
walk back in from the start of their route 6 s later.

## How it works

- `casino_patrons.gd` (feature root) spawns one `patron.tscn` per route plus the
  inherited `trump.tscn` through a `MultiplayerSpawner` on the server. Spawn data is just the index, so every peer
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

## Donald Trump

Trump (look 5) follows Mamdani along the slot aisle, staying about 1.5 metres
away and stopping when he catches up. He has blond swept hair, a navy suit, a
red tie and a name tag. Find him initially at (8.5, -1.5, -11.7).
Use E, controller B/Circle or touch USE near him: the prompt shows **-$100**.
Each accepted interaction charges the interacting player's existing wallet exactly
10,000 cents; insufficient funds leave it unchanged and show a private reply.
There is no reward or debt. The usual wallet persistence rules apply.

`trump.gd` specializes CasinoPatron's walking and talk callback, reusing its body,
combat, six-second respawn, subtitles and the feature's MultiplayerSpawner.
The server follows the mayor's current position, waits briefly for players and
collides with world geometry. If the mayor is absent he waits; after a knockdown
or respawn he resumes following. No player is used as a movement authority.
`NetworkedEntity` now declares roaming patrons' existing position, yaw, life and
ragdoll fields, including spawn snapshots. No new per-client simulation is added.
`NetworkedInteraction` validates the sender, range and standing/alive state;
requests have a half-second cooldown and each player can have only one pending
charge. Its synchronous callback launches `PlayerMoney.charge` asynchronously;
wallet idempotency and balance replication remain owned by PlayerMoney. Delayed
replies are discarded if the requester disconnects. Session changes rebuild all
patrons through the existing spawner. NPC state is not persisted.
