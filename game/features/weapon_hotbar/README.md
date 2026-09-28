# Weapon hotbar

Quick access to everything in your backpack (see `features/inventory`) without
opening the **I** screen: press **1**-**8** to grab a specific backpack slot, or
scroll the mouse wheel to cycle to the next or previous item you're carrying.
Guns also kick back when they fire.

## How it works

- `weapon_hotbar.gd` binds number keys 1-8 to one backpack slot each and the mouse
  wheel to "next"/"previous". Both call `PlayerInventory.request_equip` — the exact
  RPC the inventory screen's Equip button sends — so the server still validates
  ownership and slot bounds; this feature only decides which slot to ask for.
  Scrolling remembers the last slot it equipped so repeated notches step through
  every carried item in turn, wrapping around; an empty backpack does nothing.
- The backpack has 8 slots (`PlayerInventory.CAPACITY`), so only keys 1-8 are bound;
  9 and 0 have no matching slot.
- Mouse-wheel notches are also `Controls`' classic scroll-to-jump b-hop bind (see
  `core/input/controls.gd`), so scrolling to swap items also queues a jump — the same
  physical input, two independent reactions, same as any other shared key bind.
- `weapon_hotbar.gd` also plays a fire recoil animation on every hand's held item
  view: a quick backward-and-up kick that eases back to rest, driven by
  `features/holdables/hand.gd`'s `fired` signal (broadcast to every peer alongside
  the muzzle flash), so it's visible to everyone watching a gun go off, not just the
  shooter. Harder-hitting weapons kick more (`weapon_hotbar_math.gd`'s
  `kick_for_damage`).
- `weapon_hotbar_math.gd` keeps the recoil easing/transform and hotbar slot-cycling
  math pure and unit-tested, the same way `features/holdables/throw_math.gd` keeps
  toss math separate from `hand.gd`.
