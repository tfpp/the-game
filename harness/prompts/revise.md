## Task: revise an open pull request

`{{BRANCH}}` already implements the request below, and reviewers asked for changes. Read the
current change (`git log {{BASE_SHA}}..HEAD` and `git diff {{BASE_SHA}}...HEAD`), then the
feedback at the end of this prompt: review comments first, then `## Latest instructions` if
present. The newest instructions win when feedback conflicts.

The harness has started merging the base snapshot into this branch; inspect `git status`
and the working tree diff too. Preserve the original feature and the newer base behavior,
including changes that merge cleanly but alter shared APIs or semantics.

### How to revise

- Feedback usually comes from players who tried the PR's web preview. It's short and
  describes symptoms ("pressing forward makes the ferry go backwards", "the holes just sit
  on the floor"). Turn it into a list of concrete changes, and address every item.
- Find the cause in the code before changing anything. When something looks or moves
  wrong, work out the actual positions, rotations and facing from the scenes and scripts
  instead of nudging numbers. Then look for the same mistake elsewhere in the change.
- Pin each fix with a test where you can (a position, a direction, a rejected request).
  Re-check what `verify.sh` can't see: facing, placement against the real geometry, first
  and third person, other players and late joiners, touch and controller, and how the
  feature interacts with existing options.
- Leave the rest of the feature as it is. Don't refactor or restyle beyond the feedback.
- If the feedback only asks to update the branch ("fix conflicts", "rebase", "merge
  main"), concluding the merge is the whole task.
- Keep the changelogs describing the feature as it now works: edit this PR's own entry and
  `CHANGELOG.md` bullet rather than adding new ones. After the merge, check that the bullet
  is still under `## [edge]`: if the base has cut a release since, even a clean merge can
  leave it in the released version's section.
- While a merge is in progress, don't answer `no changes`: the harness can only conclude
  the merge with a normal summary. If you can't act on some feedback, still stage the merge
  and explain why in the summary.

In `{{OUT}}/summary.md`, the title line becomes the commit subject for anything left
uncommitted. The Summary and Changes sections describe this revision only: each piece of
feedback and what you changed for it. The three `## Integration` subsections are still
required: describe the systems this revision touched, any reuse decision it needed, and
how you checked compatibility.

{{TASK}}
