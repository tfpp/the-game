# Gun model sources

The native source is `game/features/holdables/model_tools/rifle_model.gd`.
Rebuild native parts, UV guides and animations from the project root:

```sh
godot --headless --path game -s res://features/holdables/model_tools/build_rifles.gd
```

Use `build_rifles.gd -- <kind> docs/design/model-sources/<kind>/paint_source.png`
to apply an updated paint source. Kind is mp5, m4a4 or ak47. The paint source must
preserve the exact UV chart rectangles. Runtime atlases are 128 by 128, with
nearest mipmap filtering and padding. The mask keeps grips and hardware intact
when applying skins. The AK wooden stock and handguards remain unpainted by skins.

Each folder contains an editable GLB with Frame, Bolt, Magazine and ChargingHandle,
fire/reload animation tracks, an enlarged UV template, island manifest and paint
source. Import the GLB into Blender for further modelling. The native definition
remains the rebuild source, so changes in Blender need to be brought back into
the runtime asset workflow explicitly. Model counts: MP5 572, M4A4 752, AK-47 464
triangles, including visible bore and chamber interiors.

Render all sides and re-export GLBs with the preview_rifles.tscn scene and an
absolute preview output directory after `--`. The pawn shop preview_trade.tscn
captures the actual first-person guns and a real buy/sell transaction.