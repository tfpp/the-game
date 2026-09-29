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
   - Feature `release_notes/*.json` files: preserve both additions. If two PRs picked
     the same filename for different changes, give this branch's unreleased note a unique
     issue-prefixed filename. Never rename or change a file already in a release tag.
   - Legacy `game/features/changelog/entries.gd` / `CHANGELOG.md` conflicts from older
     branches: preserve base history, migrate this branch's new entry and bullet into its
     own feature JSON file, and remove only that addition from the shared lists. Keep
     released sections intact and check for duplicated titles.
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
