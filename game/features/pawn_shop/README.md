# Pawn shop

Rusty Hogg's pawn shop is its own room west of the south corridor, mirroring the
food court on the east side. Leave the gaming floor through the south door, walk
down the corridor and turn right (west) through the doorway marked **PAWN SHOP**
at (-3, 0, 26.5). No teleports or streamed rooms. The GPS lists **Pawn Shop**.

- Room: x -16…-2, z 20…30, floor y 0, ceiling underside y 5. The live casino's
  `features/casino_hub/gridmap/shops.gd` supplies wood floor tiles and 2 × 5 m wood
  wall panels. A four-metre doorway at x -2, z 24…28 opens into the south corridor.
  This feature retains the merchant and merchandise props; its old CSG room shell
  is replaced by the saved casino GridMaps. Existing warm casino lighting applies.
- **Pawn counter** (`slum_runs`' `LootFence`, unchanged behavior) stands at
  (-11.5, 0, 24.5) with its three gold balls toward the west wall. Rusty Hogg
  (`rusty_hogg.tscn`) stands behind it facing the door. He is a `StationaryPatron`
  (`features/casino_patrons`): shootable like the salon characters, back in 6 s.
- **Gun wall** on the north wall: `wall_gun.tscn` (`WallGun`) instances hang the
  holdables pistol ($10), SMG ($25), shotgun ($30) and AWP ($50) with price tags.
  Use one to buy a copy; stock is unlimited.
- **Top hat stand** in the north-west corner at (-13.6, 0, 21.4): a wood plinth with a
  brass cap holding the tall black silk top hat (`ClothingCatalog.TOP_HAT`) for
  $10,000. It is another `WallGun` instance (`tag_position` lifts its price tag above
  the hat); buying it puts the hat straight on your head via the inventory hat slot.
- **Gun-O-Matic** and its trash can (`features/gun_machine`) stand by the south wall.

## Buying a gun

`WallGun` uses `NetworkedInteraction`: the server resolves the sender, checks range
and that the inventory has room, then charges `PlayerMoney.charge()` and hands the
gun over with `PlayerInventory.collect()`. One payment per peer can be pending per
gun. If the bag filled or the buyer left while paying, the paid gun drops on the shop
floor as an ordinary thrown item, so money is never taken for nothing. Rusty's reply
(price, "can't afford", etc.) shows as a subtitle to the buyer only. A session reset
ignores unfinished payments. Nothing is persisted beyond the wallet and inventory.

Tests: `tests/features/pawn_shop/`.

## Talking to Rusty

Step beside the counter near Rusty until **Talk to Rusty Hogg** appears, then press
E, controller B/Circle or touch USE. The nearest interaction still wins, so the
front of the pawn counter continues to offer **Pawn a valuable**. Rusty gives one
of twelve lines (the six requested in #397 plus six pawn-shop quips) as a private
subtitle, without repeating his previous line. These are text-only conversation
lines; the gun warning is a quip, not an aiming-triggered reaction.

`rusty_hogg.gd` extends `StationaryPatron`; the inherited component still owns
hitboxes, life replication and six-second respawn. Its separate `Talk`
`NetworkedInteraction` validates sender, empty payload, 2.5 m range and living
state on the server, with a shared 0.5 s cooldown. The server selects the line and
sends a private transient `say` event through the existing subtitles feature.
Late joiners see Rusty's current life state and can talk when he is alive, without
replaying old dialogue. The last line is session-only and resets on session change;
there are no per-player claims, pending payments or disconnect/respawn cleanup.
Existing purchase receipts and loot sales retain their own behavior.
