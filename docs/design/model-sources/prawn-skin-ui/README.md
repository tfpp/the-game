# Prawn skin unlock artwork

`panel-source.png` is the original artwork created with built-in ImageGen.
`paint-prompt.txt` retains the exact prompt. It supplies only the dark steel and
brass background; titles, buttons, rarity cards and painted weapon previews are
native Godot controls.

The runtime UI image is `game/assets/pawn_shop/ui/case_panel.png`, reduced to
512×512 by `game/features/pawn_shop/tools/build_skin_ui.gd`. This is UI artwork,
separate from the 128px maximum world textures. Rebuild with:

```sh
godot --headless --path game --script res://features/pawn_shop/tools/build_skin_ui.gd
```

Desktop and phone screenshots live in `docs/design/previews/prawn-skin-ui/`.
