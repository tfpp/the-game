# Ammunition cartons

Six distinct native meshes use one 128-square atlas. Each carton has 40 triangles,
a continuous bevelled body and an attached folded lid lip. Matching labels repeat
on the front and rear, with folded top and side panels.

The exact UV template, region manifest, original painting and exported GLBs are
kept here. Runtime meshes and the compact atlas live under assets/holdables/models/ammo_boxes.

```sh
godot --headless --path game -s res://features/holdables/model_tools/build_ammo_boxes.gd
godot --path game res://features/holdables/model_tools/preview_ammo_boxes.tscn
```

The preview exports GLBs and captures front, rear, underside and top views.
Stock gun purchases include one full matching box. Partial packs use the same model.
