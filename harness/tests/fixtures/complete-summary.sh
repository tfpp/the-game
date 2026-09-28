# Shared reporting fixture for fake agents in the throwaway test repositories.
[[ -s "$HARNESS_OUT/summary.md" ]] || printf 'chore: apply agent changes\n' >"$HARNESS_OUT/summary.md"
cat >>"$HARNESS_OUT/summary.md" <<'SUMMARY'

## Integration

### Systems inspected
Read game/greeting.txt, the existing greeting in this fixture repository.

### Reuse decision
Keep the greeting and extend the fixture with the requested behavior.

### Compatibility checks
The scenario verifier checks the combined tree and existing greeting where applicable.
SUMMARY
