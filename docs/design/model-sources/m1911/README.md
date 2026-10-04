# M1911-inspired player pistol

Original native geometry, based on the classic M1911 silhouette. The [Colt 1911
Classic product reference](https://coltturkiye.com/COLT-1911-CLASSIC-45-ACP-tabanca.html)
informed the slim slide, angled grip, trigger guard, exposed hammer and controls.
No reference mesh or product artwork is bundled.

## Editable assets

- `m1911.glb`: Blender-compatible mesh, UV1, material and native animation export.
- `uv_template.png`: enlarged atlas guide; the actual atlas is 128 × 128.
- `uv_manifest.json`: named islands, pixel rectangles, rotation, paint mask,
  pivots and triangle counts.
- `paint_source.png` and `paint_source_corrected.png`: original ImageGen paintings.
- `paint_prompt.txt` and `paint_correction_prompt.txt`: exact generation instructions.

The authoritative editable profiles and animation tracks live in
`game/features/holdables/model_tools/m1911_model.gd` and `m1911_animations.gd`.
The assembled game scene is `game/features/holdables/items/pistol_view.tscn`.
The meshes total 804 triangles, split into frame, slide, barrel, magazine and
hammer so each mechanical part can move. Native clips are `fire`, `reload`,
`inspect` and `RESET`; inspect is available for authoring, without a gameplay bind.

## Repainting and rebuilding

Start with the exported UV template. Paint the regions in the manifest; do not
rearrange them. Frame and slide sides have separate regions, while repeated
hardware and hidden surfaces share patches. Barrel UVs form a continuous wrap.
Every island has two pixels of padding. Import the GLB into Blender to inspect
the exact polygon UV overlay and edit the five objects.

Run from the repository root, using the installed Godot console executable:

```sh
godot --headless --path game --script res://features/holdables/model_tools/build_m1911.gd -- docs/design/model-sources/m1911/paint_source_corrected.png
godot --headless --path game --import
godot --path game --rendering-method gl_compatibility res://features/holdables/model_tools/preview_m1911.tscn -- docs/design/previews/m1911
```

The builder validates triangles and UV coordinates, resamples the painting and
extrudes island edges. The preview exports the current GLB and renders actual
geometry from both sides, front, rear, underside and animation poses. Use
`preview_m1911_game.tscn` for first-person captures of the real hand rig.
High-resolution painting sources stay outside the game export.

Stock material is painted blued steel with checkered walnut panels. Existing
prawn skins use `skin_mask.png` to paint the frame and slide while retaining
the wood, sights, bore and hardware. New texture skins can use the same UV1 atlas.

## Gameplay

The existing `pistol` item ID, purchases, pickup system and damage remain compatible.
Its seven loaded rounds are a subset of existing backpack pistol ammo. Hand still
spends one actual round per accepted shot; reload neither consumes extra ammo nor
creates any. Reload takes 1.65 seconds, blocks firing and cancels on holster or
death. A partial reserve fills only the available number of rounds. Holstering
and re-equipping cannot reset the magazine.

`PistolMechanism` uses `NetworkedEntity` for authenticated reload requests and
replicated state. Late joiners receive loaded rounds and remaining reload time;
the cosmetic view seeks into the current clip. Firing uses Hand's existing
broadcast event. The slide stays open after the final shot. Both hands follow
animated grip markers during magazine removal, insertion and slide release.
