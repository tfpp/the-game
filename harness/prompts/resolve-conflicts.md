## Task: resolve merge conflicts

The harness started merging `{{BASE}}` at `{{BASE_SHA}}` into `{{BRANCH}}`. The merge has
conflicts or the combined tree failed verification. Run `git status` and inspect the
verification output. Resolve every conflict so that both the feature on this branch
and the new work on `{{BASE}}` keep working, then `git add` the files. Don't commit and
don't abort the merge: the harness concludes it for you.

In `{{OUT}}/summary.md`, use a title like `chore: merge main into this branch`, and
describe how you resolved each conflict under Changes.

{{TASK}}
