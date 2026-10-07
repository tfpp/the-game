# Gameplay audio

Compact per-weapon gunshots plus Kenney effects for bullet impacts, animal explosions, item
collection, equipping/stowing/dropping, and opening/closing inventory. Existing
models and visual effects are unchanged.

Shots use one distinct supplied recording per weapon, with volume profiles for
pistol, MP5, M4A4, AK-47, shotgun and AWP. World sounds are positional, audible within 48 metres and
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

The operations garage uses the owner-only `van_departure` UI cue for its two-second
travel screen. It shares this feature’s GameSFX bus and bounded UI voice pool. The
original PCM source/builder is documented in `features/starter_room/README.md`;
late joiners do not hear previous trips.

The Strip Mall restaurant rivals use `city_wok_yell` / `city_sushi_yell` profiles
in the same bounded world voice pool. These are original one-second wordless
harmonic yells, authored by `strip_mall/tools/build_yells.gd`, not TV recordings;
server events trigger them only for visitors already viewing the plaza.

The metro's `metro_flatline` (features/metro) is an original 2.2-second heart-monitor
beep then flatline, 11025 Hz 8-bit, synthesized by `metro/tools/build_flatline.gd`;
no sampled game audio. A player struck by a train hears it on the UI pool; bystanders
hear it in the world pool at the impact. Late joiners do not replay it.

## Assets

Files copied unmodified from the downloaded Kenney All-in-1 pack:

- Sci-Fi Sounds: explosionCrunch_004 (animals).
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

## Compact weapon sounds

The user-provided Gun Sounds Pro - HD Remake pack supplies these clips:

| Weapon / cue | Original recording |
|---|---|
| M1911 | Pistol Shot.wav |
| MP5 | Machine Gun Shot.wav |
| M4A4 | Assault Rifle Shot.wav |
| AK-47 | Assault Rifle Shot 2.wav |
| Shotgun | Shotgun Shot.wav |
| AWP | Sniper Shot.wav |
| Shared magazine removal | Mag Out.wav |
| Shared magazine insertion | Mag In.wav |
| Shared charging | Reload.wav |

Each gun has one shooting sample. The nine WAV sources total about 55 KB, baked
as mono 11025 Hz / 8-bit PCM and imported with IMA ADPCM compression. Clips have
leading silence trimmed, normalized peaks and a 20 ms tail fade; duration is
capped at 0.8 seconds. Rebuild using tools/compress_gun_shot.gd with the source
folder after --. Source recordings stay outside the project.

The M1911, MP5, M4A4 and AK-47 share reload cues timed to removal, insertion and
charging. Accepted server reloads send transient events; cancellation stops
later stages and late joining does not replay previous sounds. Existing firing
events still play once per accepted shot, including automatic fire.