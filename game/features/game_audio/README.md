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

Each source directory includes its supplied CC0 License.txt. Only ten selected
Ogg files are included, rather than the complete asset collection.

## Checks

Run `harness/verify.sh`, plus the audio WebSocket probe under
`game/tests/features/game_audio/network_test.py`. Unit tests cover accepted and
rejected actions, shot cooldowns, effect location, voice limits and cleanup.
