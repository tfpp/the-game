#!/usr/bin/env bash
# Structural reporting check, not proof that an agent's design or claims are correct.
set -euo pipefail
if [[ ! -s "${1:-}" ]]; then
  printf 'Integration review missing: write summary.md with Systems inspected, Reuse decision, and Compatibility checks under ## Integration.\n'
  exit 1
fi
awk '
  BEGIN {
    required[1] = "Systems inspected"
    required[2] = "Reuse decision"
    required[3] = "Compatibility checks"
  }
  { sub(/\r$/, ""); sub(/[[:space:]]+$/, "") }
  /^```/ { fenced = !fenced; next }
  fenced { next }
  /^## / { integration = ($0 == "## Integration"); section = ""; next }
  /^### / { section = integration ? substr($0, 5) : ""; next }
  /^#/ { section = ""; next }
  # Do not count blank bullets or an unfilled <placeholder> from the prompt.
  integration && section != "" && /[[:alnum:]]/ && $0 !~ /^[[:space:]]*</ {
    filled[section] = 1
  }
  END {
    for (i = 1; i <= 3; i++) {
      if (!filled[required[i]]) {
        printf "Integration review missing or empty: ### %s under ## Integration.\n", required[i]
        missing = 1
      }
    }
    exit missing
  }
' "$1"
