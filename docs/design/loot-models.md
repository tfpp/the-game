# Loot models and inventory icons

The alley's four searchable dumpsters now use a painted reusable mesh. Scrap Metal
is a bent sheet with an open nut and bolt; Wallet is folded leather with a strap
and brass snap. Existing item IDs, prices, grips, loot tables and multiplayer
interactions remain owned by the existing systems.

All three albedo textures are **128×128** with nearest mipmap filtering. Repeated
panels, castors and metal parts share UV islands. Distinct island rectangles occupy
63% (dumpster), 61% (scrap) and 71% (wallet), before padding and polygon cutouts.
The deterministic polygon packer supplies the mesh, UV guide and manifest from
the same definition. Each atlas has two-pixel edge padding.

## Assets and sources

| Model | Reusable runtime scene | Native mesh, atlas and GLB | Painting source and exact prompt |
| --- | --- | --- | --- |
| Dumpster | [dumpster.tscn](../../game/features/slum_alley/dumpster.tscn) | [assets](../../game/assets/slum_alley/models/dumpster/) | [source](model-sources/loot/dumpster/) |
| Scrap Metal | [scrap_view.tscn](../../game/features/holdables/items/scrap_view.tscn) | [assets](../../game/assets/holdables/models/scrap/) | [source](model-sources/loot/scrap/) |
| Wallet | [stolen_wallet_view.tscn](../../game/features/holdables/items/stolen_wallet_view.tscn) | [assets](../../game/assets/holdables/models/wallet/) | [source](model-sources/loot/wallet/) |

The built-in image generation tool painted the supplied UV guides. Large source
images and guides stay outside `game/`; the native builder downsamples and
extrudes edge colours into the runtime atlas. Rebuilding without a source argument
preserves the painted textures.

```sh
godot --headless --path game -s res://features/holdables/model_tools/build_loot_models.gd
godot --headless --path game --editor --import
```

To apply new artwork, pass a model name and source path after `--`:

```sh
godot --headless --path game -s res://features/holdables/model_tools/build_loot_models.gd -- \
  wallet "$PWD/docs/design/model-sources/loot/wallet/generated_albedo_source.png"
```

## Rendered icons

`ModelIconRenderer` uses the actual catalog view scene, automatically frames its
mesh bounds, and renders a transparent 128×128 image with fixed lighting. Set
`ItemDefinition.icon_view_direction` for a preferred angle. Controls share one
renderer and bounded cache per viewport. Jobs run serially; the viewport renders
once for each new item and stops updating afterward. Headless servers skip it.
`request_scene` also supports scenery thumbnails, demonstrated by the dumpster.

The existing `InventoryIcon` control uses those textures for backpack and stash
slots. Item IDs still select gameplay behavior; icon rendering adds no authority
or network changes. The balance header retains its coin symbol.

Inspect or capture the actual models and inventory UI:

```sh
godot --path game res://features/holdables/model_tools/preview_loot_models.tscn
godot --path game res://features/holdables/model_tools/preview_loot_models.tscn -- \
  "$PWD/docs/design/previews/loot"
```

[Model thumbnail gallery](previews/loot/loot-model-icons.png),
[backpack](previews/loot/inventory-model-icons.png), and
[shared stash](previews/loot/stash-model-icons.png) are actual Godot captures.
The capture checks image dimensions, visible model pixels, transparent background,
uncropped borders and cache reuse. Feature tests cover UV packing, normals,
collision placement, item grips/prices, automatic framing and renderer lifetime.

## Dumpster search animation

The reusable model now splits the existing atlas into a hollow body, interior and
hinged lid. Rebuilding the dumpster also writes `body.tres`, `interior.tres` and
`lid.tres`, without changing the painted UV layout. The GLB remains a closed
static reference; the native `dumpster_model.tscn` owns the movable hierarchy.

The lid opens while `LootContainer.net_active_searchers` is nonzero, and closes
after the last viewer leaves. Search presence belongs to the existing
`NetworkedInteraction`: sender-validated use/keepalive/end requests, range and
lease checks, disconnect/reset cleanup, and replicated late-join state. Inventory
UI close, switching and destruction release presence. The fixed cover collider
does not move with the cosmetic lid.

```sh
godot --path game res://features/holdables/model_tools/preview_dumpster_search.tscn -- \
  "$PWD/docs/design/previews/loot"
```

The [closed/open capture](previews/loot/dumpster-search-animation.png) uses live
server-approved searches. Run without an output folder and press Space to toggle.
