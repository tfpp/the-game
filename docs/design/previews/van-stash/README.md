# Private van stash review

Actual native UI and rear-door scene, using existing item-model icons and theme.
The capture uses a temporary demonstration inventory and never writes a save.

```sh
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- \
  /tmp/workshop-lift-review
```

Reviewed local images (PNG files are ignored by repository policy):
`van-stash-access.png`, `van-private-stash.png`, `van-private-stash-phone.png`,
`van-private-stash-store-phone.png`. Desktop 960×540; phone 390×844.
Phone tabs and Back use 52px targets, item cards at least 130×106px, two columns,
scrollable contents and fixed navigation. Backpack cards appear before equipment.
The font scales with the existing viewport stretching and oversampling policy.

Automated coverage tests a real phone-sized tap deposit, capacity, range, doors,
lift interlock, real ENet owner-only contents and private late join, account/local
reload, failed/lost save responses, and disconnect during the save transaction.
Signed-in data shares the existing accounts SQLite inventory document. Offline
storage uses an atomic local carried/stashed snapshot. Gameplay details are in
`game/features/starter_room/README.md` and `game/features/inventory/README.md`.
