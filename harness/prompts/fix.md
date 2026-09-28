The harness checked the work on this branch, and it isn't done yet:

{{PROBLEM}}

Fix the cause; don't weaken, skip or delete checks or tests. If only the summary was
rejected, complete `{{OUT}}/summary.md`: the code doesn't need to change. Otherwise
reproduce the failing step on its own first (the failing test file, or `gdformat` and
`gdlint` on the files it names), then run `harness/verify.sh` until it passes, and keep
`{{OUT}}/summary.md` accurate. If a merge is in progress, stage the resolution and leave
the commit to the harness; otherwise commit the fix.
