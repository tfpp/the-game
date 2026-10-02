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
- `patron_model.gd` (`PatronModel`): the player avatar rig (`BlockPlayerModel` from
  `features/player_models`), posed locally each frame with the players' own walk
  cycle, idle head turns, a seated pose (`sit()`) and a sprawled pose for the ragdoll
  while the whole body topples toward the punch. Looks (`LOOKS`) pick an existing
  `PlayerSkin` tone, `PlayerAppearance` hair and `ClothingCatalog` shirt/pants colors,
  so no new textures are needed; ties, beards, glasses and badges are small boxes on
  the rig's torso and head pivots.
- Routes stay on the clear aisles of the gaming floor (y −1.25);
  `tests/features/casino_patrons/test_patron_routes.gd` sweeps every leg against the
  real room, slots and roulette.

Nothing is persisted.

## Stationary characters

`stationary_patron.gd` wraps the salon characters in layer-2 hitboxes fitted to their
mesh bounds, or to a body's posed `hitbox_bounds()`. The salon guests
(`stationary_guest/seated/lady.tscn`, `salon_guest_model.gd`) are `PatronModel` rigs
turned to face +Z: standing guests idle and look around; seated guests and ladies sit
on the card-table chairs (0.48 m seats, thighs dipping so the feet reach the floor)
with both hands resting on the felt. Each picks a dinner suit or evening dress from
its position, and is re-posed about ten times a second only while visible. The old
imported salon character meshes were removed. Salon guests, dealers, bartender
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

## Ambient smoking

Three existing guests in the **live GridMap casino** smoke: the standing guest at
the main bar (-8.2, -1.25, -8.25), the west seat of the northern card table
(-7.16, -1.25, -5.10), and the lady at the southern table (-5.5, -1.25, 4.95).
Just walk over and watch; no controls, purchases or inventory changes are involved.
Other guests, dealers, named roaming patrons and vendors keep their existing poses.

`SalonGuestModel.smoking` is an opt-in presentation flag set on those bodies in
`casino_hub/gridmap/furnishings.tscn`. `PatronSmoking` reuses the painted holdables
cigarette, its Mouth/Grip markers, the avatar's `mouth_transform()` and existing
arm/finger IK. Each ten-second loop eases the cigarette to the mouth, holds a draw,
lowers the hand and exhales. Seated guests retain their seat/feet pose and left hand
on the felt. Timings are offset by the existing guest look seed.

Smoke uses two small world-space CPU emitters (8 tip wisps + 20 exhale wisps per
smoker), camera-facing procedural soft quads, growth and alpha fade curves.
There are no new textures, lights, shadows, colliders or model exports.
Smoker posing runs at up to 30 Hz within 18 m of a camera; distant, hidden and
headless guests stop emitting and clear old clouds. Death follows the existing
replicated `net_alive` visibility; respawning resumes presentation without stale
smoke. These are local cosmetic loops, like dealer hand motion: peers may see
different puff timing, and late joiners see a fresh loop, never a replayed event.
No new RPC, shared state or persistence is introduced.

Coverage: `tests/features/casino_patrons/test_smoking.gd`, original rig/life tests
and the existing ENet stationary life test. To inspect the actual rig and shader:

```sh
godot --path game res://tests/features/casino_patrons/smoking_probe.tscn -- \
  --smoking-capture=/tmp/smoking.png
```

Add `--smoking-exhale`, `--smoking-seated` or `--smoking-back` for other views.
The capture needs a graphical renderer; it is not a browser performance benchmark.

## Donald Trump

Trump (look 5) follows Mamdani along the slot aisle, staying about 1.5 metres
away and stopping when he catches up. He has blond swept hair, a navy suit, a
red tie and a name tag. Find him initially at (8.5, -1.25, -11.7).
Use E, controller B/Circle or touch USE near him to bribe him. The price doubles
with each bribe: $100, $200, $400, $800, $1,600 (`Trump.bribe_price()`), charged
through the existing wallet; insufficient funds leave it unchanged and add nothing.
After a paid bribe he privately promises to remodel part of the casino, picked from
1,000 generated quips (`trump_quips.gd`: 10 openers × 10 areas × 10 plans).
Each bribe gives a 20% chance per slot spin of one extra roll of the reels if it
loses (`favor_rerolls()`, group `trump_favor`, read by `SlotMachine`), so five
bribes guarantee one extra roll: a 4% spin becomes about 7.8%. Favor is never spent.
After five bribes he takes no more money. Counts live in server memory per peer,
reset on disconnect or session change, and the owning client gets its own count
through a private `bribes` event for the prompt price. The extra roll only affects temporary (offline / insecure-auth) wallets until the
accounts API accepts rerolls. Kaaba blessings are separate and also apply to signed-in
wallets; favor retries a losing blessed spin once with ordinary 4% odds.

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

## Mitch McConnell

Mitch (`PatronModel.MITCH_LOOK`, `mitch.tscn` / `mitch.gd`) sits in a wheelchair
pushed by a blond intern, looping `PatronMath.MITCH_ROUTE`: up the east aisle
(x 12), across at z 2 and back down the mayor's slot aisle (x 8.5). The intern and
wheelchair are part of `MitchModel` (`mitch_model.gd`), so the group is one
networked patron with the usual punches, gibbing and six-second respawn.

Every 7–14 s the server sends a cosmetic `_throw_peace_sign` RPC and every peer
raises his right hand in a peace sign for 2.5 s. When Trump comes within 0.9 m
(`Trump.can_pat()`), the server stops both for 2 s and sends `_pat_head`: Trump
reaches out and pats him, a "Good boy." bubble floats over Trump for everyone,
and players within 10 m also get it as a subtitle. Pats have a 15 s cooldown.
Gestures are transient, so late joiners just see the next one.

## Card dealers

The three salon card dealers (`card_dealer.tscn`) use the player avatar rig
(`BlockPlayerModel` from `features/player_models`) instead of the imported salon
pose. They wear a black vest, white shirt and red bow tie: `human_surface.gdshader`
gained a `tuxedo` switch that paints the torso with
`assets/casino_patrons/textures/dealer_tux.png` (64×64, painted by
`assets/casino_patrons/source/paint_tux.gd`) and the sleeves white; black trousers
reuse the existing pants tint. `CardDealerModel` reaches both hands (arm IK via
`SkinnedHuman.reach_grip`) to points about 20 cm over the felt and drifts them in
small out-of-phase loops (`hand_target()`), each dealer offset by `seed_phase`.
The motion is local and cosmetic, runs only while visible, and needs no network
state; dying, respawning and hitboxes still come from `StationaryPatron`.
The bartender, apartment clerk and roulette croupier (`stationary_dealer.tscn`) wear
the same tux with `dealing = false`: they stand at ease and glance around.
`tests/features/casino_patrons/dealer_probe.tscn` renders a close-up
(`-- --dealer-capture=/tmp/dealer.png`, add `--dealer-back` for the back).
