# Pawn shop

Rusty Hogg's pawn shop occupies the former Stardust Rec Room in the southwest
casino corner. Walk west from the south lobby; the GPS lists **Pawn Shop**.
The casino supplies its floor, ceiling, north wall and outer walls.

- Shop area: x -34…-18, z 21.2…34, floor y 0, open to the lobby on the east.
- **Pawn counter** (`slum_runs`' `LootFence`) stands at (-29.5, 0, 25.7).
  Rusty Hogg stands behind it at (-30.7, 0, 26.4), facing customers to the east.
- **Gun wall** on the north wall sells the pistol ($10), SMG ($25), shotgun ($30)
  and AWP ($50). Use one to buy a copy; stock is unlimited.
- **Top hat stand** at (-31.6, 0, 22.6) sells the $10,000 top hat.
- **Gun-O-Matic** at (-24.5, 0, 29.6) and its trash can at (-26.3, 0, 29.9)
  share the shop. Existing casino lighting illuminates the area.

## Buying a gun


`WallGun` uses `NetworkedInteraction`: the server resolves the sender, checks range
and that the inventory has room, then charges `PlayerMoney.charge()` and hands the
gun over with `PlayerInventory.collect()`. One payment per peer can be pending per
gun. If the bag filled or the buyer left while paying, the paid gun drops on the shop
floor as an ordinary thrown item, so money is never taken for nothing. Rusty's reply
(price, "can't afford", etc.) shows as a subtitle to the buyer only. A session reset
ignores unfinished payments. Nothing is persisted beyond the wallet and inventory.

Tests: `tests/features/pawn_shop/`.
