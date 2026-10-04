# Slum excursions

Main-casino overhead door signs were removed in issue #487. Door placement,
Use prompts, GPS routing and remote return signs remain unchanged.

The Golden Crown elevator starts private group excursions through
`features/zone_instances`. Its occupants travel together to their own copy of the
garage or Rain Alleys; returning, dying or disconnecting removes membership.
Each new instance starts with fresh searchable containers. The south lobby gate
is now scenery and has no interaction script.

`SlumRuns` keeps death-drop and post-respawn messaging in the existing inventory
and combat flow. Its legacy `begin` API remains for development fixtures while
the normal elevator creates instances directly through `ZoneInstances`.

Each private slum has a return elevator. Surviving players bring valuables back in their
inventory. The pawn shop counter (`Fence`, `loot_fence.gd`) inside Rusty Hogg's pawn shop
(`features/pawn_shop`, off the south corridor), marked by three gold balls and a glass display case, buys one valuable per Use press at
the price on its `ItemDefinition`; the sale goes into the same wallet used by
slots. Items are reserved before an online sale starts. If the accounts API
does not answer, pressing Use again retries the same operation ID, so the
database cannot pay twice. The API stores each sale and rejects retries with
a changed account or amount. Offline/dev wallets use the same prices.

If a player is killed during an excursion, the server drops their carried
valuables at the death site as ordinary pickups. Other players can collect
them. Weapons, clothes and keys remain with the respawned player. After the
respawn in the Crown, the victim sees a short toast naming each dropped valuable
and confirming their weapons were kept (`SlumRuns.death_penalty_message`).
The toast reuses `LootToast` with a longer duration. Deaths in
the Crown and its other rooms do not drop valuables.

The registered `SlumArrivalPoint` selects the destination for the Crown elevator;
`SlumInstance` builds its private map and return cab. Extend that instance builder
and its spawn data when adding destinations. Keep searchable containers and shared
actors outside client-only streamed geometry. Legacy shared-map return doors
remain development fixtures, rather than the integration path for new excursions.
