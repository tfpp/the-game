#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/chicken_betting/network_probe.tscn
port=17894
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
for role in observer driver; do
  godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name="Bird-$role" --chicken-role="$role" >"$logs/$role" 2>&1 &
  pids+=("$!")
done
for ((i=0; i<350; i++)); do
  if grep -q FIGHT_STARTED "$logs/driver"; then break; fi
  if grep -qE 'SCRIPT ERROR|ERROR:' "$logs"/*; then break; fi
  sleep 0.1
done
grep -q FIGHT_STARTED "$logs/driver" || { tail -80 "$logs"/*; exit 1; }
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=BirdLate --chicken-role=late >"$logs/late" 2>&1 &
pids+=("$!")
for ((i=0; i<400; i++)); do
  if grep -q DRIVER_DONE "$logs/driver" && grep -q WALLET_RESULT_PASS "$logs/observer" && grep -q LATE_FIGHT_SNAPSHOT_PASS "$logs/late"; then break; fi
  sleep 0.1
done
grep -q RANGE_REJECTED "$logs/driver"
grep -q UPFRONT_DEBIT_PASS "$logs/driver"
grep -q UPFRONT_DEBIT_PASS "$logs/observer"
grep -q LATE_FIGHT_SNAPSHOT_PASS "$logs/late"
grep -q DRIVER_DONE "$logs/driver"
grep -q WALLET_RESULT_PASS "$logs/observer"
if grep -E 'SCRIPT ERROR|ERROR:' "$logs"/*; then exit 1; fi
printf 'Chicken real-peer debit, fight, payout and late-join checks passed. Logs: %s\n' "$logs"
