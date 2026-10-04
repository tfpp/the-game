# Phase 1 mechanics delivery

The first PR ships the gameplay loop. Performance and cosmetic resource unloading
are deferred to `perf/phase-one-part-two`; the complete pre-split working state is
preserved in the named Git stash, including its untracked files.

## Mechanics

- Server-owned private group excursions to the garage or Rain Alleys, with scoped
  players, enemies, loot, actions and state. Global chat remains shared.
- Crown and return elevator cabs support four riders, validated doors, overload
  feedback, cab-relative transfers, readiness acknowledgements and short rides.
- Five garage floors use saved GridMaps, ramps, stairs and jump/drop shortcuts.
  Loot and enemy pressure increase on deeper floors; wetness increases below B1.
- Crown spawn and safe-zone firing/damage restrictions.
- Retired shared garage mock-up and slum gate; updated development travel routes.
- Modeled fixed signs, readable arrivals and an empty hotbar that collapses on phones.

## Validation

Before the split, the full GUT suite passed 2,196 tests and 426,130 assertions.
That run still reported existing exit resource diagnostics and is not a passing
repository gate. Focused multiplayer tests cover group isolation, late state,
outsider rejection, lifecycle cleanup and elevator readiness. Native captures
reviewed arrivals, enemy silhouettes and portrait/landscape HUD layouts.

The separated mechanics change must pass `harness/verify.sh` before commit or PR.
Changes in `game/core/` require human review under the repository guide.

## Part 2

F4 browser performance acceptance and the broader active-zone-only resource
requirement remain open. Cosmetic streaming, avatar animation guards and the web
profiling fixture are parked. The latest callback diagnostic is experimental:
normal garage sampling was about 39 FPS, while pausing 26 body callbacks reached
about 65 FPS with collision and player physics active. It does not establish a
production fix or acceptance; the native game was running concurrently.

## Integration with current main

The split was updated to main at 8ca7eb33, retaining its new UI, songs and tax desk.
The integrated hotbar passes 38 tests and 113 assertions. Native captures cover
360x780 and 780x360, empty and occupied: empty panels hide, while occupied slots
retain main's theme, touch targets and compact sideways scrolling.

Final combined gate: harness/verify.sh passed on current main plus the mechanics
change. GUT passed 2,218 tests and 429,293 assertions; offline and multiplayer
smoke checks and bot/api Go checks passed. Existing exit diagnostics remain
(139 ObjectDB instances and two resources); the required gate returned zero.
