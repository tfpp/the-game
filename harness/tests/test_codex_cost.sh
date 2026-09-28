#!/usr/bin/env bash
# Bounded API-equivalent estimates from fake Codex events, never billed CLI cost.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
adapter="$here/../adapters/codex.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/out"
export PATH="$work/bin:$PATH" HARNESS_OUT="$work/out"
export CODEX_TEST_EVENTS="$work/events"
unset HARNESS_MODEL HARNESS_REASONING_EFFORT
cat >"$work/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$HARNESS_OUT/args"
cat >/dev/null
printf '%s\n' '{"type":"thread.started","thread_id":"cost-test"}'
cat "$CODEX_TEST_EVENTS"
EOF
chmod +x "$work/bin/codex"
printf 'prompt\n' >"$work/prompt"

call() {
  "$adapter" "$work/prompt" "$work/log" "$1" >/dev/null
  if [[ "$1" == 1 ]]; then
    [[ "$(head -2 "$HARNESS_OUT/args" | tr '\n' ' ')" == 'exec resume ' ]]
  fi
  [[ "$(grep -A1 '^-m$' "$HARNESS_OUT/args" | tail -1)" == "${HARNESS_MODEL:-gpt-6-astra}" ]]
  grep -qx 'model_reasoning_effort="low"' "$HARNESS_OUT/args"
}
check() {
  jq -e "$1" "$HARNESS_OUT/usage.json" >/dev/null
}

for cont in 0 1; do
  echo "- codex cost: continue=$cont"
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":15747,"cached_input_tokens":13056,"cache_write_input_tokens":0,"output_tokens":5}}' >"$CODEX_TEST_EVENTS"
  call "$cont"
  check '.input_tokens == 2691 and .cache_read_tokens == 13056 and .output_tokens == 5 and .cache_write_tokens == 0 and .cost_usd == 0.040216 and .models == ["gpt-6-astra"] and .cost_basis == "standard short-context token estimate; excludes tool fees"'

  # Multiple events sum once; preserve existing cache-write accounting separately.
  printf '%s\n' \
    '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":200,"cache_write_input_tokens":100,"output_tokens":10}}' \
    '{"type":"item.completed","usage":{"input_tokens":99999}}' \
    '{"type":"turn.completed","usage":{"input_tokens":2000,"cached_input_tokens":500,"cache_write_input_tokens":300,"output_tokens":20}}' >"$CODEX_TEST_EVENTS"
  call "$cont"
  check '.input_tokens == 2300 and .cache_read_tokens == 700 and .cache_write_tokens == 400 and .output_tokens == 30 and .cost_usd == 0.0302'

  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}' >"$CODEX_TEST_EVENTS"
  call "$cont"
  check '.cost_usd == 0 and .input_tokens == 0 and .output_tokens == 0 and .cache_read_tokens == 0 and .cache_write_tokens == 0'

  # Aggregated totals above 272K do not identify any single long-context request.
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":300000,"output_tokens":100}}' >"$CODEX_TEST_EVENTS"
  call "$cont"
  check '.cost_usd == 3.005 and .cache_read_tokens == 0 and .cache_write_tokens == 0'

  for model in unknown-model gpt-6-astra-custom; do
    HARNESS_MODEL="$model" call "$cont"
    check ".cost_usd == null and .models == [\"$model\"] and .cost_basis == \"unavailable: unsupported model\" and .input_tokens == 300000"
  done
  HARNESS_MODEL=gpt-6-astra call "$cont"
  check '.cost_usd == 3.005 and .models == ["gpt-6-astra"]'
done
echo 'codex cost tests passed'
