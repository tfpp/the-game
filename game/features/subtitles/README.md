# Subtitles

NPC dialogue shows like movie subtitles: a centred line near the bottom of the screen,
`Speaker: line`, with the speaker name in gold on a translucent black strip. It stays up
for 2.5 s plus 0.05 s per character (at most 7 s), fades out, and a new line replaces it.

`Subtitles.say(get_tree(), speaker, text)` shows a line on the calling peer only. It is
presentation, not state: the NPC's server code decides who hears a line (for example
`NetworkedInteraction.send_event(&"say", …, peer)`) and each receiving client calls
`say()`. Nothing is replicated or persisted. Used by `features/casino_patrons` (Mamdani
and Trump). The strip sits above the weapon hotbar and ignores the mouse, so it works in
first and third person, on touch and with a controller.
