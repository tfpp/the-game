# Weapon hotbar

Quick access to every weapon you're carrying without opening the **I** screen: press
**1**-**8** to grab a specific backpack slot (see `features/inventory`), **9** to
bring back a holstered gun machine gun (`features/gun_machine`), or scroll the mouse
wheel to cycle to the next or previous slot in either system. The weapon panel at the
bottom of the screen (top on touch screens) shows what's in your hand with its ammo,
then all nine slots. Tap or click a slot to equip it; the picked slot (or the rig)
stays highlighted while you hold something. Guns also kick back when they fire.

In first person, number-key and mouse-wheel swaps lower the handheld and arms for
0.12 seconds, send the existing equip request, then raise the selected item over
0.22 seconds: a 0.34-second animation layered over sway and bob. Rapid selections
replace the pending choice and continue from the current pose. Clothing equips
and third-person switching retain their immediate behavior.
Firing is blocked through both phases. Clicks during the swap are ignored; an
automatic gun's held trigger resumes firing after the animation finishes. Recoil
keeps weak references to weapon views so replacing a model safely clears its recoil.

## How it works

- `weapon_hotbar.gd` binds number keys 1-8 to one backpack slot each, 9 to
  `features/gun_machine`'s rig, and the mouse wheel to "next"/"previous" across both.
  Backpack slots reuse `PlayerInventory.request_equip` — the exact RPC the inventory
  screen's Equip button sends — and the rig slot reuses `GunRig.request_equip_rig`;
  either way the server still validates ownership, so this feature only decides
  *which* slot to ask for. Scrolling remembers the last slot it equipped so repeated
  notches step through every carried weapon in turn (backpack slots, then the rig),
  wrapping around; nothing carried does nothing.
- The backpack has 8 slots (`PlayerInventory.CAPACITY`), so only keys 1-8 are bound
  to it; 9 is reserved for the rig, and 0 has no matching slot.
- Only one weapon is ever equipped: equipping a backpack weapon holsters the rig
  (`PlayerInventory.holster_weapon`/`_holster_gun_rig_if_weapon`), and equipping or
  re-selecting the rig holsters whatever's in hand (`GunRig.equip`/
  `request_equip_rig`, via `PlayerInventory.holster_weapon`). Holstering a gun keeps
  it — the rig's `net_stats` survive, a holdable weapon just moves back to an empty
  backpack slot (or gets dropped if the backpack is full) — so switching away and
  back never costs you the weapon.
- `weapon_hotbar_hud.gd` draws the weapon panel: a header with the held item (gold while
  it's a weapon) and its ammo (`gun_stats_panel.gd`'s `ammo_text()`), then backpack
  slots 1-8 and the rig (9), each labeled with its contents. `ui/hud_layout.gd` places
  it bottom-center, across the bottom on narrow screens, or at the top for touch.
  Every cell carries a flat `Tap` button that calls `weapon_hotbar.gd`'s
  `equip_slot()`. Narrow and touch layouts keep 52-unit (44pt+) cells with short names
  in a sideways-scrolling row; the panel joins the `touch_hud` group so
  `features/touch_controls` leaves taps on it alone. It hides under the pause menu.
- `weapon_hotbar.gd` also plays a fire recoil animation on every hand's held item
  view: a quick backward-and-up kick that eases back to rest, driven by
  `features/holdables/hand.gd`'s `fired` signal (broadcast to every peer alongside
  the muzzle flash), so it's visible to everyone watching a gun go off, not just the
  shooter. Harder-hitting weapons kick more (`weapon_hotbar_math.gd`'s
  `kick_for_damage`).
- `weapon_hotbar_math.gd` keeps the recoil easing/transform and slot-cycling math
  pure and unit-tested, the same way `features/holdables/throw_math.gd` keeps toss
  math separate from `hand.gd`. `next_occupied` is the general cycle used for both
  the backpack-only case (`next_slot`) and the backpack-plus-rig case.
