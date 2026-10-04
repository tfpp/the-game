# Pawn shop street ambience

User-supplied recordings from the original asset folder:
`Road Ambiance Loop Thunders.wav` and its `_1` through `_4` variations.
The five runtime WAVs retain the original durations and are reduced to mono
11025 Hz / 8-bit PCM, then imported with Godot's QOA compression.
Original files are retained in the user's source folder.

Rebuild with Godot using `--headless --path game --script
res://features/pawn_shop/tools/compress_city_audio.gd -- <source-folder>`.
