# İstanbul Kebab

A Turkish kebab counter in the southeast casino food court (`features/food_court`), against its
east wall at (30.2, 0, 28.5), rotated so its front, staff and sign face west into the
hall. The GPS lists **İstanbul Kebab** and routes to the cashier's customer side at
(28.7, 0, 29.85). The counter and its GPS marker moved together from the former south wing. No light is added.

Use **E / B / Circle / touch USE** in front of Aylin to order a complimentary
kebab. Orders place it in an empty hand or the existing backpack. Make room if both
are full. Eat the equipped kebab with the existing primary action (left click,
controller attack or touch FIRE); inventory, dropping and sharing work as with
bananas. Food has no additional healing benefit. Free opening-day service is the
chosen price because the request did not specify one.

Chef Kemal carves beside a rotating layered döner spit. Aylin is an adult cashier
with a fitted emerald uniform, dark wavy hair and gold jewelry. Her greeting changes
to “Afiyet olsun!” with a serving gesture for three seconds after each order.
The detailed dürüm includes flatbread, toasted marks, a paper sleeve, shaved meat,
lettuce, tomato, onion and yogurt sauce. Staff are stationary shop attendants, not
combat targets or moving navigation agents.

`NetworkedInteraction` resolves the sender and checks range, the customer side of
the counter and idle service state. Its synchronous server callback transfers the
item through `PlayerInventory.collect`; no duplicate inventory or wallet exists.
Failed/full/missing inventories do not start service. Successful orders immediately
transfer ownership, so disconnects cannot leave pending orders; inventory retains
its usual respawn/disconnect semantics. Competing requests serialize behind the
three-second service animation. The server clock and service state replicate to
late joiners; session changes reset them. Only nearby clients pose the cosmetic
meshes. No state is persisted by this feature; kebabs follow ordinary inventory
lifetime. Offline uses exactly the same server path.

Tests: `tests/features/kebab_shop/` and `tests/features/food_court/`, alongside the
existing inventory and holdables suites. No new controls or shared method signatures.
