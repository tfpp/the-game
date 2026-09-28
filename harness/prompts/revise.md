## Task: revise an open pull request

`{{BRANCH}}` already implements the request below, and reviewers left feedback. Read the
current change (`git log {{BASE_SHA}}..HEAD` and `git diff {{BASE_SHA}}...HEAD`), then address
the feedback. The harness has started merging the base snapshot into this branch; inspect
`git status` and the working tree diff too. Preserve the original feature and the newer
base behavior, including changes that merge cleanly but alter shared APIs or semantics.
The newest instructions win when feedback conflicts.

In `{{OUT}}/summary.md`, the title line becomes the commit subject for anything left
uncommitted, and the Summary and Changes sections describe this revision only.

{{TASK}}
