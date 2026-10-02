# Lucky Five upright cabinet

`cabinet-reference.png` is an AI-generated design reference, not a photograph or
an in-game screenshot. It guides the narrow dark enclosure, raked reel window,
projecting button deck, illuminated red/gold glass, coin tray and two-tier beacon.
General web reference browsing was unavailable in the working environment.

`build.gd` is the editable native mesh source. It exports a 1,392-triangle cabinet
using the existing 128px material atlas. The moving lever and reel drums remain
separate runtime parts. The cabinet's side profile and frames are modeled geometry.

`glass-uv-template.png` defines the two padded art charts. ImageGen painted this
template; its original output and exact painting prompt are retained alongside it.
`paint.gd` extracts the two painted regions, reduces them to a 128px atlas and
extrudes chart gutters. Live labels remain legible independently of the artwork.

From the repository root, with Godot 4.7 on PATH:

```sh
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v3/build.gd
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v3/paint.gd
godot --headless --path game --editor --import --quit
mkdir -p /tmp/slot-v3
godot --path game --rendering-method gl_compatibility --audio-driver Dummy -s ../docs/design/model-sources/slot-cabinet-v3/review.gd -- /tmp/slot-v3
```

The review script renders the actual reusable gameplay scene, including a front,
three-quarter, rear, underside, spinning, winning and casino placement view.
Mechanical audio from v2 is retained. The runtime scene uses this cabinet and a
matching narrow collision hull; the live reels, readout and lever still follow
authoritative spin results.
