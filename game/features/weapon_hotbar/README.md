# Weapon hotbar

Quick access to every weapon you're carrying without opening the **I** screen: press
**1**-**8** to grab a specific backpack slot (see `features/inventory`), **9** to
bring back a holstered gun machine gun (`features/gun_machine`), or scroll the mouse
wheel to cycle to the next or previous slot in either system. A strip at the bottom
of the screen shows all nine slots and highlights whichever one is actually in your
hand. Guns also kick back when they fire.

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
- `weapon_hotbar_hud.gd` draws the bottom-center strip: the hand, backpack slots 1-8,
  then the rig, each labeled with its contents and highlighted gold while it's the
  weapon actually in hand.
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
