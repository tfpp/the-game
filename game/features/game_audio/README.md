# Gameplay audio

Kenney sound effects for all four guns, bullet impacts, animal explosions, item
collection, equipping/stowing/dropping, and opening/closing inventory. Existing
models and visual effects are unchanged.

Shots use short arcade blasts with separate volume/pitch profiles for pistol,
SMG, shotgun and AWP. World sounds are positional, audible within 48 metres and
attenuated with distance. Inventory cues are local to the owner and success cues
only play after the server accepts the action. Gun cooldowns also gate sound;
shotgun pellets produce one shot and at most one impact sound per trigger.

The `elevator_ding` cue (features/elevator) reuses the confirmation chime at a
brighter pitch rather than adding another audio file.

Shot events carry the weapon ID and firing position, so later equipment changes
do not alter their audio. Reliable authority-only events reach current peers;
late joiners do not replay old effects. Dedicated servers skip playback.

The GameSFX bus includes a limiter. Playback is bounded to 24 simultaneous world
sounds and four UI sounds; oldest voices are removed at capacity. Finished voices
free themselves. Changing network mode clears pending sounds. World voices live
under this feature so an explosion's visual cleanup cannot truncate its sound.

## Assets

Files copied unmodified from the downloaded Kenney All-in-1 pack:

- Sci-Fi Sounds: explosionCrunch_000 (pistol/SMG), _002 (shotgun/AWP), _004 (animals).
- Impact Sounds: impactGeneric_light_000 (surfaces), impactPunch_medium_000 (hits).
- Interface Sounds: open_001, close_001, select_001, confirmation_001, drop_001.

Each source directory includes its supplied CC0 License.txt. Only the selected Ogg clips are included.

Door and key clips come from RPG Audio in the supplied Kenney All-in-1 3.7.0 ZIP:
`doorOpen_1`, `doorClose_2`, `metalLatch`, `metalClick` and `handleCoins2`.
The supplied CC0 license is alongside them. Door movement/unlock sounds use
NetworkedEntity transient server events. A denied lock attempt is heard only by its
requesting player, limited to once per 400 ms; key collection is owner-only too.
There are no floating door labels or lock-status prompts. Late joins replay no sounds.

## Checks

Run `harness/verify.sh`. Unit tests cover accepted and
rejected actions, shot cooldowns, effect location, voice limits and cleanup.
