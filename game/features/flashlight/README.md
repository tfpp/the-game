# Flashlight

Press **F** to toggle an always-available flashlight, initially off. Rebind
**Flashlight** under Settings → Controls → View. Chat, menus and other modal UI
suppress the toggle. It works alongside held items without consuming an item slot.

The beam follows the player's eye position and yaw/pitch, including in third person
(the light stays on the player, not the pulled-back camera). A warm spotlight reaches
24 meters and casts shadows so walls block it.

`request_toggle` validates the actual sender against existing players and changes
only that sender's switch on the server. The server-owned `Sync` replicates the
`enabled_peers` snapshot, including on late join. Each peer renders cosmetic lights
from that snapshot and existing player movement; no extra player movement or inventory
state is stored. Disconnect removes the switch; changing sessions resets all lights.
