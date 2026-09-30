# Slum excursions

The Golden Crown's south lobby gate starts a shared excursion. The first player
through chooses a registered slum arrival point; later players join that same
map until everyone returns, dies or disconnects. A new excursion resets
searchable containers. The old parking garage no longer has a casino staff
door; only this gate reaches it.

Each slum has a return door. Surviving players bring valuables back in their
inventory. The pawn shop counter (`Fence`, `loot_fence.gd`) inside Rusty Hogg's pawn shop
(`features/pawn_shop`, off the south corridor), marked by three gold balls and a glass display case, buys one valuable per Use press at
the price on its `ItemDefinition`; the sale goes into the same wallet used by
slots. Items are reserved before an online sale starts. If the accounts API
does not answer, pressing Use again retries the same operation ID, so the
database cannot pay twice. The API stores each sale and rejects retries with
a changed account or amount. Offline/dev wallets use the same prices.

If a player is killed during an excursion, the server drops their carried
valuables at the death site as ordinary pickups. Other players can collect
them. Weapons, clothes and keys remain with the respawned player. Deaths in
the Crown and its other rooms do not drop valuables.

New slum scenes register a `SlumArrivalPoint` on their arrival marker and
can use a `GarageDoor` to return to `slum_runs/CasinoArrival`. Put searchable
containers in the new area and add a GPS destination.
