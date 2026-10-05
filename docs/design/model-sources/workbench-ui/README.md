# ImageGen workshop UI art

`paint-source.png` is the original ImageGen painting; `paint-prompt.txt` records
the exact prompt. The generated blueprint panel has no baked words or buttons.
The image remains preserved at its original generated-image path as well.

```sh
godot --headless --path game -s ../docs/design/model-sources/workbench-ui/build.gd
```

The native importer writes `game/assets/starter_room/workbench_blueprint.png` at
128×128, imported with mipmaps. The workbench uses it as a decorative panel behind
native model icons, live stats and salvage counts. Gear selection and the Install
button remain authenticated gameplay controls. Desktop/landscape layouts put the gear list beside the blueprint detail panel;
phones stack a two-column selection grid above it. Both keep 60px footer actions
fixed beneath a scrolling body.
