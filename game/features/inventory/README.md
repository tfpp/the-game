# Inventory and clothing

Press **I**, the controller **View/Back** button, or **Inventory** in the Esc menu.
The screen uses the project's Kenney panel and button assets. It shows a live
character preview, equipment and an eight-slot backpack. The top-right coin and
balance read the existing wallet and never occupy a slot. Select an item to equip,
store or drop it. The screen pauses gameplay input while open.

Players start barefoot in white underwear, with no equipment or backpack items.
Use the existing **E / B / Circle / USE** interaction to collect items. Pickups
fill the matching empty equipment slot first (hand, shirt or pants), then use the
backpack. Equipping a backpack item swaps it with the current item in that slot,
even when the bag is full. Eating and throwing affect only the held item.

Searching a car or dumpster opens its shared stash beside your backpack. Drag
an item to an empty slot, or tap it to fill the next empty slot. Other players
see items disappear as they are claimed.

Shirts and pants have fixed colors. Find other colors to change your outfit;
there are no dye controls. Two clothing pickups sit near spawn, two to the west,
and two to the east. Clothes keep their color through swaps, drops and pickups.
White underwear reappears when pants are removed; it cannot be stored or dropped.

## Multiplayer

`PlayerInventory` is a child of the existing server-spawned `Hand`. Its inventory
and clothing are synchronized from authority 1, including to late joiners.
Clients request slot operations; they cannot supply new item IDs or target peers.
The server checks sender ownership, slot bounds, bag capacity and pickup distance.
Repeated pickup/drop requests cannot duplicate items. The avatar and held arms
read replicated clothing, so other players see equipment changes too.

Inventory follows the existing held-item lifetime: it survives an in-session
combat respawn, but is cleared on disconnect or a network mode change. It is not
saved between sessions. World pickups follow the existing one-use pickup system.

Run `harness/verify.sh` and
`GODOT=godot python3 game/tests/features/inventory/network_test.py` from the repo root. Feature tests cover capacity, swaps, consumption, fixed
colors, invalid and foreign requests, drops, pickups and underwear visuals.
