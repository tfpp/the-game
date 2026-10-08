# Casino liquor, drunkenness and blackouts (#538)

Random drinks stand all over the Golden Crown. Pick one up with **E / B / Circle /
touch USE** (it goes into your hand, or the backpack if the hand is full; equip it
through Inventory), then drink with the primary action (**left click / RB / trigger /
touch FIRE**). Each sip takes three seconds and shows the existing drinking animation
to everyone.

| Drink | Sips | Model |
| --- | --- | --- |
| Bottle of whiskey | 3 | casino whiskey bottle |
| Bottle of red wine | 3 | casino wine bottle |
| Dry martini | 1 | martini glass, olive on a pick |
| Whiskey on the rocks | 1 | rocks glass, amber pour, two ice cubes |
| Cosmopolitan | 1 | cocktail glass, pink pour, lime wheel |

Every sip is **one drink** of the intoxication that `features/bar_companion` already
owns (beer and the bartender's "Drink now" count too, as before). Intoxication still
wears off one drink every 90 s and keeps its charisma rules.

## Where the drinks are

Twelve spots (`BoozeRules.SPOTS`), each on a real surface, clear of existing decor,
busboy glasses, table cards and Vivienne's case papers:

- salon bar counter: three spots between the bar's own bottles and glasses;
- the three salon card tables, at the east guest's elbow;
- the four walnut promenade cocktail tables (west lounge and tables 6–8);
- the mariachi balcony bar: two spots.

The bars' painted tops sit 15 cm above their colliders, so bar drinks use the drawn
height (-0.12 and 6.13). Every spot starts each session with a random drink
(cocktails a little more often than bottles). A taken drink is replaced with another
random one 60–150 s later. Drinks are ordinary inventory items afterwards: they can
be stored, dropped, shared and saved like the bar's beer.

## Being drunk

The effects grow with each drink and peak at seven (`BoozeRules.intensity`). They
ease in and out over a few seconds and only run on the drinker's own client:

- **Tipsy (1–2):** a slow camera roll and a gentle drift in aim.
- **Drunk (3–5):** double vision with a wobbling ghost image and a dark vignette;
  walking weaves left and right.
- **Hammered (6–7):** about ten degrees of roll, stronger aim drift and sideways
  stumbles every few seconds.

Aim drift changes the real view angles, so shots still follow the crosshair. Weaving
and stumbles change only your own client-authoritative velocity on the ground, so
other players simply see you stagger. Menus stop the drift. Remote players draw no
effects for you and no new input is needed on desktop, controller or touch.

## Blackouts

The **eighth** drink (`BoozeRules.BLACKOUT_DRINKS`, out of BarCompanion's ten)
blacks you out, GTA style:

1. **Collapse (3 s):** whatever you hold goes into your backpack and you fall flat on
   your back while your screen fades to black. You cannot walk away or drink more.
2. **Out:** "You blacked out." Your shirt, pants and hat come off (packed into free
   backpack slots; anything that does not fit is dropped where you fell, as a normal
   pickup) and you sober up to zero drinks. The server picks a random metro station
   and a lane beside one of its tracks.
3. **Wake (6 s):** you come to lying in your underwear on that platform, eyelids
   opening with a blink: "Ugh... where are your clothes?" After 4.5 s you get up.
   Re-equip clothes from Inventory and take a metro elevator home.

Everyone sees the body lie down and stand up, including late joiners. Bodies lie
along the platform, about 1.3 m clear of the tracks. Your inventory is otherwise
untouched. If you black out in a private excursion you leave it first. If the metro
cannot take you within 30 s, you wake where you fell. Death ends a blackout early.

## Multiplayer and ownership

- `Booze` (`booze.gd`, group `booze`) is the server owner of blackout phases. Its
  `NetworkedEntity` replicates `blackouts` (peer → phase) on change, including to late
  joiners. It is also the `consumption_group` handler (`can_consume` / `consume`) for
  the five drinks, so the existing `ConsumableUse` component does sender, hand,
  payload and state checks. It never trusts a client for drinks, phases or targets.
- `BarCompanion.drink_added(peer, intoxication)` (new signal) triggers blackouts for any
  drink source; `BarCompanion.sober_up(peer)` (new) resets intoxication.
- `PlayerInventory.stow_equipment(slots)` (new) empties hand/clothing slots into the
  backpack, dropping overflow through the existing holdables spawner.
- `MetroService.deliver(player, position, yaw)` (new) reuses the metro's readiness
  handshake (`MetroTransfers`, kind `wake`): the drinker's client loads the station and
  reports its floor before the server teleports them; `delivered(peer)` then starts the
  wake-up. `cancel_delivery(peer)` abandons only such a drop-off.
- `DrinkSpot` (`drink_spot.gd`) is a static `NetworkedInteraction` endpoint per spot.
  Its `net_item` replicates on change; Use validates sender, range, empty payload and
  inventory space on the server, so two players cannot take the same drink.
- `DrunkView` (`drunk_view.gd`) is local presentation and the local player's movement:
  it pins a blacked-out player in place (accepting server teleports), adds sway after
  the camera is placed, and draws the double vision (`drunk_screen.gdshader`, layer 0,
  under the HUD) and the blackout screen (layer 19). The full-screen pass is hidden
  while sober, so sober players pay nothing; there are no new lights or textures.
- Disconnects, deaths and session resets clear blackouts. Drink stock, blackouts and
  drunk visuals live in server memory; intoxication keeps BarCompanion's existing
  account persistence and clothing/backpack changes save through the inventory API.

## Checks

GUT: `tests/features/booze/` (rules, drinks and spots, blackout flow with the real
metro, local presentation and live-casino layout). Rendered review (needs a display):

```sh
godot --audio-driver Dummy --rendering-method gl_compatibility --resolution 1100x750 \
  res://tests/features/booze/booze_visual_probe.tscn -- --offline
```

It writes `/tmp/booze-<view>.png` for the bar, tables, promenade, lounge, balcony,
a lying body, drunk vision and a real blackout ending on a metro platform.
