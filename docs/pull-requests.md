## Pull Requests

- PR titles should follow a conventional commit format: `type(scope optional)!: short description`.
- Squash commits should be enabled.
- Use [the PR template](../.github/pull_request_template.md):

```markdown
## Summary
Brief explanation of the PR and why it's needed.

## Changes
- **Change**: description of what changed.

## Validation
- Checks run and their results.

## Agent Usage
| Metric | Value |
| --- | --- |
| Model(s) used | Exact model IDs, including additional models if used |
| Reasoning effort | Reasoning or thinking effort the model ran with (e.g. low), or Unavailable |
| Tokens used (input + output + cache reads/writes) | Total tokens for this run, including retries |
| Estimated cost (USD, API-equivalent) | Estimated USD cost, or Unavailable |

## Discord Request
> Original Discord request, if applicable.

– requested by Discord username
```

The harness fills usage from its telemetry rather than asking the model to guess.
Generated PRs describe the implementation run; subsequent push comments describe their
own revision or conflict-resolution run, not lifetime PR totals. Unknown telemetry is
`Unavailable`, not zero. Human-only PRs may use `None (human-authored)` and `Not applicable`.
Costs estimate API-equivalent usage, not the amount billed to a subscription. Codex's
GPT-6 Astra estimate uses standard short-context token rates and excludes long-context
premiums and separate tool fees; unsupported model pricing remains unavailable.
