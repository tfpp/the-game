# Garage finishes review

Rendered in Godot 4.7.2 with the native Compatibility renderer. Local review
captures: `alley-window.png`, `alley-exterior.png`, `garage-shutter.png` and
`broom-cupboard.png`. PNG previews are ignored by repository policy.

Regenerate all operations room views with the existing starter-room capture scene:

```sh
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- /tmp/garage-finishes-review
```

Reviewed the real wall opening, outdoor rain, street-prop depth, painted shutter
hardware and cupboard supplies. Floating debug labels are absent. Rain particles
remain outside the garage; weather and audio are owned by streamed alley content.
