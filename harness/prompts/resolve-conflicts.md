## Task: resolve merge conflicts

The harness started merging `{{BASE}}` at `{{BASE_SHA}}` into `{{BRANCH}}`. The merge has
conflicts, or the combined tree failed verification (the failure output then follows at the
end of this prompt). Finish the merge so that both the feature on this branch and the new
work on `{{BASE}}` keep working, then `git add` the files. Don't commit and don't abort the
merge: the harness concludes it for you.

This is a merge, not a feature review. Skip the design review under "Before coding", and
don't refactor, restyle or extend either side.

1. List the conflicts: `git status` and `git diff --name-only --diff-filter=U`.
2. Resolve each one so that both sides' changes survive:
   - `game/features/changelog/entries.gd`: both sides added entries at the top of
     `ENTRIES`. Keep every entry whole, in the multi-line shape from "Changelogs", with
     unique titles and this branch's entry first.
   - `CHANGELOG.md`: keep every bullet, without duplicates. This branch's bullet belongs
     under `## [edge]`. If `{{BASE}}` has cut a release since, its old edge bullets moved
     into a version section: check that this branch's bullet didn't move with them, even
     if the file merged cleanly.
   - READMEs, tests and lists that both sides appended to: keep both additions.
   - Code: combine both sides' changes. Where they disagree about a shared interface, keep
     `{{BASE}}`'s version, which other features already use, and adapt this branch's code.
3. Check what merged cleanly, too. `{{BASE}}` may have renamed or removed something this
   branch uses, and a combined test file can exceed gdlint's 20 public methods; split it by
   concern.
4. Format what you edited, run the tests of both sides' features, then `harness/verify.sh`.

In `{{OUT}}/summary.md`, use the title `chore: merge {{BASE}} into this branch` and describe
how you resolved each conflict under Changes. Fill in all three `## Integration`
subsections: **Systems inspected** lists the conflicted files and the base changes that
touch this feature, **Reuse decision** says which side's interfaces you kept and how you
adapted the other, and **Compatibility checks** names the tests that cover both sides.

{{TASK}}
