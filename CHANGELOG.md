# Changelog

Every notable change, newest first. `edge` is what's on `main` but not released yet.

**In every pull request with a change players, operators or contributors would notice, add
a bullet to the end of `## [edge]`:** imperative, one line per change where possible, no
version. Releases are cut by hand (the `release` workflow): it moves `edge` into a section
for the new version. See "Versioning" in [docs/architecture.md](docs/architecture.md).

## [edge]

- Character Model (Esc menu) now picks a body, a head and a tail independently: a
  frog head or bird head, and a lizard, fin or fluffy tail, on any body (including
  the girl and penguin builds), so you can mix and match your own impossible
  creature.
- Add a day/night cycle: a full day repeats every 48 real-time minutes, with the sun
  swinging across the sky, the skybox fading between day and night, and ambient
  lighting dimming at night. It runs off the real-world clock, so it stays in sync
  for everyone without any extra networking.
- Rank connected players by wallet balance and show a swarm of flies over the poorest
  80% of them, rounded down; nobody is flagged with fewer than two connected wallets.
- Frogs jump twice as high by default now, with a new "Frog jump height" slider in
  Game settings (Esc > Settings > Game) to tune it further; they also bounce off walls
  at an oblique angle mid-hop instead of stopping dead, ribbit when shot, and there are
  now 12 of them instead of 6.
- Version releases by hand from the `release` workflow, which picks the patch, minor or
  major bump, tags it, publishes a GitHub Release and shows the version in the HUD.
- Keep this changelog, with an `edge` section rolled into each release.
- Group the in-game release notes (`L`) by version, showing the last 10 releases and what's
  new since the latest one.
- Announce each release in Discord once it is live, with its changelog notes, and each
  deploy's new edge changes as "New on edge".
- Add a Game settings page (Esc > Settings > Game) to tune jump height and frog hop rate
  for everyone in the world.
- Switch the UI to Inter (body), Exo 2 (headings), Barlow (buttons) and Orbitron (HUD
  readouts), and put the release notes on a light sheet with palette-matched headings.
- Deploy the accounts API automatically when its image is built, so API changes (like the
  wallet endpoint) no longer wait for a manual deploy.
- Add `/close` to the Discord bot: in a feature thread, it closes the feature's PR without
  merging and its issue as not planned.
- Close a Discord feature's issue automatically when the agent makes no changes for it.
- Show each agent run's token usage and estimated cost in its PR and in the Discord thread.
- Give the girl model a smaller collision hitbox and 15% less passive income.
- Add `/usage` to the Discord bot: it shows how much of Claude's 5-hour and weekly usage
  limits the agent has used, and when they reset.
- Add sprays: press T to spray a decal on the surface you're looking at, visible to
  everyone (placeholder image for now).
- Add 1960s brass wall sconces to the annex corridors and rooms, dim by day and
  glowing at night, so they no longer go pitch black after dark.

## [0.6.0](https://github.com/tfpp/the-game/releases/tag/v0.6.0) - 2026-09-28

Versioning starts here, matching milestones v0.1 to v0.6. Highlights so far:

- Source-style movement multiplayer on the web, with a dedicated server on the homelab.
- Accounts with Discord or email sign-in, and join tickets checked by the game server.
- Discord bot: `/feature` and `/revise` agent runs, approvals, a merge queue and automatic server deploys.
- Money: a persisted wallet, income over time, coins, a slot machine, a roulette table and a gun machine.
- Weapons and combat: an AWP, SMG and shotgun, a hotbar, recoil and item drops.
- The world: an expanded map with connected rooms, the Gilded Lily casino, an elevator, a pond,
  trampolines, the NYC ferry, frogs, gnomes, a penguin, a Kaaba landmark and a soccer ball.
- Chat, push-to-talk voice chat, a third-person camera, noclip, a Settings menu with rebindable
  controls and audio, and an in-game changelog.
