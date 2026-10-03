# City restaurant review

Native Godot 4.7.2 Compatibility / Mesa llvmpipe captures from the real main
scene, at 1280×720. These are rendered assets, not concept art. Source renders alone did not catch
export repacking discarding City Sushi's nested overrides: the Sushi instance now
has an explicit editable declaration. The regression test repacks the scene and
checks its sign, Junichi costume and owner placement; a Web export pack was also
loaded headlessly to confirm CITY SUSHI, character=1 and position=(-2,0,0).
These captures still describe native source rendering, not browser rendering.
They predate the paid-food revision, so their DISPLAY ONLY boards are historical;
current boards advertise $12/$15 bowls. Run the new food_probe below for current menus.

- `rival-plaza.png`: opposing counters, broad clear aisle, existing Żabka bay.
- `city-wok.png`: orange vest, red bow, blue pants, balding hair and shout pose.
- `city-sushi.png`: white gi, dark sash/pants, black hair and answering bubble.

The probe freezes the server scheduler only for these captures; production
runs alternating four-second turns. Checked grounded counters/feet, customer
facing and readable nearby labels/bubbles. Browser, mobile and controller play
and actual listening were not manually tested. Dummy audio validates playback
paths but does not constitute a listening review. Native full-level renderer
shutdown reports the existing two GL texture leaks; no script errors occurred.

Reproduce from the repository root:

```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/strip_mall/capture.tscn -- /tmp/city-restaurants
```

Current paid-food review (both menus, offline purchases and first/third-person bowls):

```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/strip_mall/food_probe.tscn
```

Captures are written to `/tmp/CityWokShop-*.png` and `/tmp/CitySushiShop-*.png`.
Both reuse the existing salmon/rice bowl model; no new food art was introduced.

These scenes reuse the repository's counter meshes, grain/materials, display
bowl/cup and human rig/textures. Added costume boxes use native primitive UVs
and solid material tints, not new painting sources. Original synthetic audio
has no third-party samples and rebuilds with strip_mall/tools/build_yells.gd.
Character costume references (not shipped artwork):
https://southpark.wiki.gg/wiki/Tuong_Lu_Kim and
https://southpark.wiki.gg/wiki/Junichi_Takiyama.
