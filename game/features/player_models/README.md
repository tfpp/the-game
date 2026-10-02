# Custom player models

Adds an original textured low-polygon human avatar under each existing `Player/Body`,
with the natural proportions and small painted textures of late-1990s PC shooters.
A single connected, skinned GLB mesh replaces the box construction. Bones deform
its vertices at shoulders, elbows, hips and knees; blend shapes modify build,
hair and tactical clothing on the same topology. Players start barefoot in white underwear. The inventory supplies equipped
shirts and pants with fixed colors, replicated for everyone to see. The existing F3 camera displays your own model in third person;
your body remains hidden in first person.

## Body, head and tail

Open **Esc → Settings → Character Model** to mix and match a body, a head and
a tail, independently, like an impossible creature: a girl body with a frog head
and a fish fin, a default body with a bird head and a fluffy tail, and so on. The
picker shows a live preview in your current skin tone and clothing. Each choice is
just a request; the server validates it and replicates it to everyone (through `NetworkedEntity`), so other players always see the same combination you picked. Every
axis defaults to the original build and none are saved between sessions.

**Body** is the original default build, a girl variant (narrower shoulders and
waist, wider hips, and longer hair), or a penguin costume. **Head** is the
original human face, a wide-mouthed frog face, or a beaked bird head. **Tail** is
none, a tapering lizard tail, a fish fin, or a round fluffy tail; it attaches
behind the hips on any body, including the penguin costume.

The penguin body replaces clothing and the head entirely (it's a full costume,
not an outfit, so the head choice above has no effect while it's selected) and
scales the whole rig down to `BlockPlayerModel.PENGUIN_HEIGHT_SCALE` (see
`block_player_model.gd`) so it reads as short as the penguin NPC
(`features/penguin`). `BlockPlayerModel.height_scale()` exposes that scale so
`features/holdables/hand.gd` can shorten your first-person view model — the held
item and hands — to match, without holdables needing to know about body types.
The penguin NPC itself notices a nearby player wearing this costume and waves a
flipper and hops in place at them; see `features/penguin/penguin.gd`.

The girl body's collision capsule is 60% as wide and 75% as tall as the default
capsule, with its bottom kept at the same height. Its avatar and eyes now follow
the same shortened height, and the penguin's capsule/eyes follow its costume. It earns $4.25 instead of $5 per
minute connected; the $20 starting balance, map coins and game prizes are
unchanged. Head and tail choices are purely cosmetic: they don't affect the
collision capsule or income.

## ID-based height

Players automatically get one of eleven standing heights (**1–3 m**, in 20 cm steps) from
their authenticated account ID. Reconnecting, respawning and server restarts
recompute the same height; offline/dev-auth players use their peer ID instead.
No menu or key is needed; **F3** shows your own size. This works on desktop,
controller and touch without additional inputs.

The server's account name **Sor** (case-insensitive, trimmed) overrides the ID
height to **eight feet / 2.4384 m**.
There is no known account ID for Sor in this repository, so the special case uses
the authenticated name, not a client-supplied player label. Dev-auth preview
servers can use `--name=Sor`; an ordinary offline peer 1 keeps the original height.
Normal girl/penguin body multipliers compose with ID height, clamped to **1–3 m**
so even the shortest normal costume is at least one metre tall. Sor remains eight
feet in every body, preserving the deliberate exception. Crouching still lowers
the capsule and eye further. Offline peer 1 without an account retains the original
1.8288 m build; authenticated account ID 1 uses the same variety as other accounts.

`PlayerModels.heights` replicates only derived metres via its existing
`NetworkedEntity` (including late joins); account IDs stay server-side and no
height request is registered. `height_scale_for(peer)` reports the final standing
factor. `PlayerHeight.eye_scale(player)` reads the applied factor for camera,
crouch and equipment integration. Each player gets a private movement resource:
only eye height changes, not speed, jump, gravity, hull reference height or authority.
Capsules and avatars scale about their feet, nameplates follow the new head level,
and the camera near plane shrinks for tiny players so their scaled held items
and first-person emotes remain visible. Both weapon systems keep their existing
damage, ammo, range and inventory state.

Height is derived session state, not new persistent storage. Disconnect/session
cleanup clears it; server identity restores it when a player returns. Tests in
`test_player_height.gd` cover identity stability, Sor in every body, crouch/respawn,
feet/eyes/equipment and snapshots. The real-network probe checks both normal and Sor heights and their applied
avatar/capsule scales on the server, owner and late observer, and rejects attempted
height requests. Range regressions check both endpoints, every body type, repeated
application, camera/equipment alignment and independent late-spawned players.

## Skin tones

Pick one of eight skin tones, five hairstyles, five hair colors and four eye colors,
plus **Casual** or **Tactical** outfits
on the Character Model settings page. Drag the preview with a mouse or touch to
inspect the back and sides. Skin, hair, eye and outfit choices persist locally with
`SettingsStore` and are requested again after reconnects; the server validates
the complete appearance payload, and late joiners receive the same appearance.
Hair and eye options are retained when using a creature head or costume and
reappear when switching back to human. Clothing stays inventory-owned.

With **Automatic** skin tone, a player's ID selects one of eight skin tones. The server uses the authenticated
account ID, so a reconnect with a new network peer ID keeps the same tone. Offline
and dev-auth players use their peer ID. Hand spawn data carries only the resulting
palette index; account IDs remain on the server. Avatars, bare arms and legs,
gripping hands, and the inventory preview all use the same skin color. Clothing
and white underwear keep their own colors.

## Animation

`block_player_motion.gd` derives poses from velocity:

- Idle below 0.12 m/s, blending limbs back to rest.
- Walking below 55% of the player's configured maximum speed.
- Running above that threshold, with longer strides, stronger arm swing and lean.
- Jump takeoff and falling poses, followed by a brief landing compression.
- Seated (legs forward, hands towards the table) while the `seating` group's
  `is_seated(peer)` says so (food court booths).
- Crouched and crouch walking while the `crouching` group's `is_crouching(peer)`
  says so (`features/crouch`): thighs forward, knees bent back through the skinned
  calf bones, torso leaning forward and the rig lowered so the feet stay planted;
  moving adds a short alternating step. The crouched collision capsule is 72% as
  tall, anchored at the feet.

Stride phase advances with horizontal speed, with reversed steps when backing up
and side lean when strafing. The model blends pose transitions and turns its head
with view pitch. This adds no sprint binding or gameplay speed changes. Accepted boxing swings
layer a lead-arm extension and bent guard arm over locomotion, closing both fists
on the skinned mesh. Jabs lead left; power punches lead right. Penguin flippers
use the same arm pivots. `Boxing.arm_pose(peer)` is the read-only source; held
items retain priority and the arms blend back to locomotion after the swing.

Local models use the player's velocity and floor contact. Remote models use
existing replicated velocity and a short floor ray to distinguish standing from
the apex of a jump. Animation is cosmetic and does not write shared network state
or need extra RPCs. The feature attaches rigs to new players and respawns once;
rigs are children of players and disappear with them.

## Held items

`Hand.support_grip()` exposes the existing item support marker. The human skeleton bends its arms to the item grips, keeping the same connected
mesh visible; free arms keep swinging. The penguin costume and first-person view
reuse the same skinned human asset with non-arm surfaces masked out. `Hand` follows the animated shoulder markers and shirt
color. One-handed items leave the other arm free; two-handed weapons keep both
grips while the legs continue animating. First-person hands keep their existing
camera mount. Each hand has a thumb and four separate fingers with three weighted
joints each. Fingers relax when unarmed and curl around item grips; palm bones
follow grip orientation. Existing items with distant support markers extend the
arm joint translations to reach them without scaling the hands or fingers.

Run `harness/verify.sh`. Tests under `tests/features/player_models` cover locomotion,
backwards and sideways movement, airborne detection, landing, model attachment,
visibility, the item-grip integration, and the body model choice (validation,
replication and rebuilding without losing clothing or skin tone).


## Integration and verification

`SkinnedHuman` caches the imported rig's fixed rest transforms and checks actual
bone values before writing a pose, avoiding skeleton updates for unchanged bones.
Reading actual values preserves the reset of item IK and emote overlays. Patron
callers defer `BlockPlayerModel.animate()`'s skeleton pass until their NPC pose
adjustments are complete; player callers retain the default immediate pass.

`PlayerModels` owns appearance, body/head/tail choices and their session lifecycle.
Its legacy RPC adapters now delegate to `NetworkedEntity`; the picker uses the
component directly. No player movement or core scene changes are needed.
`Hand.skin_tone_index()` resolves the same server-owned skin override, keeping
first-person hands and the backpack preview consistent with the world model.
The joint pivots and shoulder markers keep their original paths and clothing
materials so held items, camera visibility and creature combinations still work.
Disconnects clear all choices for that peer; local saved appearance is requested
again in a new session. These preferences are per device, not account storage.

Run `game/tests/features/player_models/network_test.sh` for real server/client
appearance and all four selectable emotes, sender identity, invalid payload and
late-join checks (Godot and bash only). Run `game/tests/features/player_models/visual_probe.tscn` in Godot for a
four-avatar contact sheet, optionally passing `-- --avatar-capture=/tmp/avatars.png`.


## Art and outfits

All human geometry and seven 128×128 textures are original. The editable model
is `assets/player_models/source/human.blend`, with reproducible authoring scripts
beside it. Runtime uses one connected mesh, one shader surface, forty-five bones and
five blend shapes. Geometry is shared across avatars; vertex morph weights and
material tints are per instance. See `assets/player_models/README.md` for source
commands and mesh budgets. The legacy `BlockPlayerModel` class name remains for
compatibility with existing callers.

Casual uses inventory shirts and pants. Tactical morphs the same chest and boots,
with painted vest and gear detail. With empty clothing slots it supplies olive
fatigues; equipped clothing colors still apply underneath the gear. Changing
outfit does not equip, spend, remove or duplicate inventory items. Previous saved
preferences without an outfit remain valid and default to casual. Creature
heads, tails and the penguin costume retain their existing appearance.


## Networked emotes

Hold **B** (controller left-stick click) to open the radial emote wheel. Move the
mouse or left stick toward a slice, then release to perform **Flip off**, **Wave**,
**Salute** or **Cheer**. The center, Esc or right-click cancels. The wheel pauses local
movement/look/actions, not the server. On touch, open **Pause → Emotes** and tap a
slice; this menu entry also supports mouse click or left-stick selection + A.
Rebind under **Settings → Controls → View → Emote wheel (hold)**. The action ID
`emote_flip_off` is retained so saved bindings still work. Focus loss, session
changes and player replacement dismiss the wheel without sending a request.

All gestures last three seconds with the existing 3.5-second per-player cooldown;
requests during cooldown are ignored. Wave swings an open hand, Salute holds flat
fingers to the brow, and Cheer pumps a raised fist. They use only the left hand,
leaving the equipped right-hand item in place. Emotes are transient session state,
not saved preferences. The original Flip off gesture
raises the left hand, curls the thumb/index/ring/little fingers, holds the middle
finger straight, then lowers the arm. It overlays walking and running without
changing movement. The first-person hand follows the camera; third-person
observers see the avatar's weighted arm and finger bones perform the same emote.

`PlayerModels` owns a validated `emote` action through `NetworkedEntity`. Clients
send only the supported name; identity comes from the authenticated sender. The
server checks the player exists, enforces a separate 3.5-second cooldown per
player, and stores the start time against a continuously replicated server clock.
Clients interpolate that clock locally. Late joiners wait for its snapshot and
resume the current animation phase. The server removes finished/despawned emotes;
disconnect and session-reset paths clear state and cooldowns.

`emote_view.gd` applies the pose after normal locomotion and item-grip updates.
An equipped item stays in the right hand while the left support hand gestures,
then resumes its support pose. First-person emote geometry reuses the same
connected human mesh. The penguin costume masks the human body and substitutes
its left flipper with the rigged gesture hand for the animation.

Run the real server/client/late-join regression:

```sh
game/tests/features/player_models/network_test.sh
```

`tests/features/player_models/emote_probe.tscn` renders third person; add
`-- --first-person-emote` for the camera hand with a held weapon. The optional
`--emote-elapsed=0.15` selects an animation phase and `--avatar-capture=/tmp/emote.png`
saves a screenshot. GUT coverage includes invalid/forged requests, ownership,
independent cooldowns, clock-snapshot ordering, expiry/disconnect/despawn/reset,
finger articulation, camera switching, and weapon/costume restoration.

`BlockPlayerModel.mouth_transform()` supplies a world-space mouth contact for held
consumables, following the animated head and costume scale. Holdables moves its
existing grip toward that contact; the existing skinned arm IK performs the smoking
and drinking gesture without a second avatar or movement authority change.

The surface shader's `tuxedo` / `tux_texture` parameters (off for players) paint a
vest texture on the torso and white sleeves; see the card dealers in
`features/casino_patrons/README.md`.

### 6-7 emote

Whenever any wallet lands on **$67** in whole dollars (cents are ignored, so $67.00
through $67.99 count), every connected player performs the "6-7" emote for three
seconds: both hands held out palms-up, see-sawing up and down like scales. It is
server-triggered only: `PlayerMoney._set_balance()` calls
`PlayerModels.emote_everyone()`, which writes a `six_seven` entry for each player
into the same replicated `emotes` state (so late joiners, expiry and disconnect
cleanup behave like flip-off). Clients can't request it. A wallet that stays within
$67 doesn't retrigger; it has to leave and come back. Render it with
`emote_probe.tscn -- --emote-name=six_seven`.
