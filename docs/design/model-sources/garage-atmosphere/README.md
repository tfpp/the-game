# Garage atmosphere and road scenery

```sh
godot --headless --path game -s ../docs/design/model-sources/garage-atmosphere/build.gd
```

The native builder exports saved road GridMaps with wet asphalt, grey sidewalks,
painted dashed markings and distant brick frontage. It reuses the alley's 128px
brick/asphalt library and the existing garage floor material; no CSG or runtime
construction. `road_view.tscn` adds existing lamp, service-door and parked-car
meshes as scenery without vehicle loot or travel interactions.

The four-metre shutter aperture is sealed by an always-present invisible collision
boundary. Players cannot walk or jump onto the road. Garage
membership/safe-zone bounds remain unchanged; rendering bounds include scenery.

The builder also exports original mono 22,050Hz PCM loops: 4s fluorescent hum,
12s quiet radio melody and 2s motor rumble. Compressed AudioStreamWAV resources
play through GameSFX. No external recordings or runtime audio synthesis.

Personal details reuse native hotel/casino props. The fixed shutter frame
(48 triangles) and moving leaf/handle (332) come from the garage-finishes builder
and share its approved 128px atlas. Review the native shutter opening/road and
new generated-art workbench in phone/landscape captures.
