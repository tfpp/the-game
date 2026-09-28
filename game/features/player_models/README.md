# Block player models

Adds an original voxel-style avatar under each existing `Player/Body`. Cuboid
heads, torsos, separate arms and legs, and pixel face details replace the capsule
visual. Players start barefoot in white underwear. The inventory supplies equipped
shirts and pants with fixed colors, replicated for everyone to see. Player collision and movement
are unchanged. The existing F3 camera displays your own model in third person;
your body remains hidden in first person.

## Body model

Open the Esc menu and pick **Character Model** to switch between the default build
and a girl variant: narrower shoulders and waist, wider hips, and longer hair. The
picker shows a live preview in your current skin tone and clothing. Your choice is
just a request; the server validates it and replicates it to everyone (like
clothing), so other players always see the same model you picked. It defaults to
the original build and is not saved between sessions.

## Skin tones

A player's ID selects one of eight skin tones. The server uses the authenticated
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

Stride phase advances with horizontal speed, with reversed steps when backing up
and side lean when strafing. The model blends pose transitions and turns its head
with view pitch. This adds no sprint binding or gameplay speed changes.

Local models use the player's velocity and floor contact. Remote models use
existing replicated velocity and a short floor ray to distinguish standing from
the apex of a jump. Animation is cosmetic and does not write shared network state
or need extra RPCs. The feature attaches rigs to new players and respawns once;
rigs are children of players and disappear with them.

## Held items

`Hand.support_grip()` exposes the existing item support marker. Occupied avatar
arms are hidden while Holdables draws its gripping hands and blocky arms;
free arms keep swinging. `Hand` follows the animated shoulder markers and shirt
color. One-handed items leave the other arm free; two-handed weapons keep both
grips while the legs continue animating. First-person gloves keep their existing
camera mount.

Run `harness/verify.sh`. Tests under `tests/features/player_models` cover locomotion,
backwards and sideways movement, airborne detection, landing, model attachment,
visibility, the item-grip integration, and the body model choice (validation,
replication and rebuilding without losing clothing or skin tone).
