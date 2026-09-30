# Pawn shop

Rusty Hogg's pawn shop is its own room west of the south corridor, mirroring the
food court on the east side. Leave the gaming floor through the south door, walk
down the corridor and turn right (west) through the doorway marked **PAWN SHOP**
at (-3, 0, 41.5). No teleports or streamed rooms. The GPS lists **Pawn Shop**.

- Room: x -14.5…-3.5, z 35…44.5, floor y 0, ceiling at y 5.5. The north wall is the
  casino's south outer wall, the south wall is the south-wing bend corridor and the
  east wall is the annex corridor (`features/annex` owns the `PawnShopDoorway` cut).
  Two `wall_sconces` light it at night.
- **Pawn counter** (`slum_runs`' `LootFence`, unchanged behavior) stands at
  (-11.5, 0, 39.5) with its three gold balls toward the west wall. Rusty Hogg
  (`rusty_hogg.tscn`) stands behind it facing the door. He is a `StationaryPatron`
  (`features/casino_patrons`): shootable like the salon characters, back in 6 s.
- **Gun wall** on the north wall: `wall_gun.tscn` (`WallGun`) instances hang the
  holdables pistol ($10), SMG ($25), shotgun ($30) and AWP ($50) with price tags.
  Use one to buy a copy; stock is unlimited.
- **Top hat stand** in the north-west corner at (-13.6, 0, 36.4): a wood plinth with a
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
