# Working workshop review

Actual Godot Compatibility renders show the shutter closed/open, rainy road,
furnished workbench and generated-art upgrade menu at 960×540,
390×844 and 844×390.

```sh
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- /tmp/road-ui-review
```

Local PNGs are ignored by repository policy. Phone review checks readable text,
106px gear cards, model previews, damage comparisons, material counts and fixed
60px Install/Back controls. Landscape puts the gear list beside the detail panel.
An invisible full-height collision boundary stays fixed while shutter
geometry/collision clears the opening, keeping players inside, including jumps.
