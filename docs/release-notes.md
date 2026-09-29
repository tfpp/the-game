# Release notes

Each notable change owns a new file at
`game/features/<owner>/release_notes/<issue>-<short-description>.json`.
Use a unique descriptive name when there is no issue. Two PRs changing the same feature
still use different files. Revisions edit their own unreleased file.

```json
{
  "title": "Jump pads",
  "summary": "Step on a glowing pad to launch high into the air.",
  "notes": ["Add jump pads to the lobby."]
}
```

The title is globally unique; the summary is a short player-facing sentence. `notes`
contains one or more single-line imperative bullets without a bullet prefix. JSON escaping
handles quotes and Unicode. These are the only fields. Use the nearest affected feature
for cross-cutting work; release tooling belongs to `changelog`.

Do not append to `CHANGELOG.md` or `game/features/changelog/entries.gd`. Both retain legacy
history, including old branches during the transition. Old release tags remain readable.

The in-game panel discovers feature files, also in web and server exports. Export filters
include the JSON files. Release grouping still comes from reachable `vX.Y.Z` tags: an entry
belongs to the first release containing its title. With no tags, all notes are on edge.
File paths are sorted for deterministic collection; historical entries keep their order.

`scripts/feature_notes.sh` uses Godot's JSON parser and Git to validate notes and
collate titles or edge bullets. It runs a standalone GDScript project without game
autoloads or asset imports, using the same Godot runtime as exports. `harness/verify.sh`
invokes it and the release regression scripts via the game checks.
`scripts/release.sh` collects files absent from the latest
reachable release tag and rolls their bullets, plus legacy edge, into `CHANGELOG.md`.
It does not delete, rename or edit feature notes. The release tag marks them as released,
so the following release does not repeat them. Only release automation edits the shared
markdown history and version. Preview edge bullets with:

```bash
scripts/feature_notes.sh edge WORKTREE
```

The Discord bot reads files at the deployed commit and compares their paths with the
latest live release tag. Existing announcement tracking prevents reposting notes on each
deploy. Adding a file after a release—even from a branch started before that release—puts
it on edge automatically.

Keep released files immutable, including their paths and titles. Add a new file for a
later improvement. Duplicate titles, malformed JSON, empty fields, and modifications to
released notes fail validation. For an older open PR, move only its new shared-list entry
and bullet into its own JSON file, preserving upstream and released history.
