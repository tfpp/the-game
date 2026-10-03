#!/usr/bin/env bash
# Real server, visitor and late visitor exercise the existing frog protocol.
set -euo pipefail
game="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT
fail() { tail -n 80 "$tmp"/*.log; exit 1; }
wait_for() {
  for ((i=0; i<600; i++)); do
    if grep -q 'ERROR:' "$tmp"/*.log; then fail; fi
    if grep -q "$2" "$1"; then return; fi
    sleep 0.05
  done
  fail
}
port="$((22000 + RANDOM % 20000))"
spawn() {
  local role="$1"
  local args=("--connect=ws://127.0.0.1:$port")
  if [[ "$role" == server ]]; then args=(--server "--port=$port"); fi
  touch "$tmp/$role.log"
  godot --headless --path "$game" res://tests/features/strip_mall/network_probe.tscn -- \
    --dev-insecure-auth "--frog-role=$role" "--name=$role" "${args[@]}" \
    > "$tmp/$role.log" 2>&1 &
  pids+=("$!")
}
spawn server
wait_for "$tmp/server.log" 'Server listening'
spawn visitor
wait_for "$tmp/visitor.log" FROG_CLIENT_DEAD
wait_for "$tmp/visitor.log" CITY_FOOD_PURCHASED
spawn late
wait_for "$tmp/late.log" FROG_CLIENT_DEAD
wait_for "$tmp/server.log" FROG_SERVER_RESPAWNED
wait_for "$tmp/visitor.log" FROG_CLIENT_RESPAWNED
wait_for "$tmp/late.log" FROG_CLIENT_RESPAWNED
wait_for "$tmp/visitor.log" RIVALRY_CLIENT_SYNCED
wait_for "$tmp/late.log" RIVALRY_CLIENT_SYNCED
wait_for "$tmp/late.log" CITY_FOOD_PURCHASED
echo "PASS: Żabka frogs, City rivalry and purchases/forged prices/late-join food snapshots"
