#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/irs_desk/network_probe.tscn
port=${IRS_TEST_PORT:-17893}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=IRSDriver --irs-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<200; i++)); do
  if grep -q IRS_PAID "$logs/driver"; then break; fi
  sleep 0.1
done
grep -q IRS_PAID "$logs/driver" || { tail -80 "$logs/driver"; exit 1; }
timeout 25 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=IRSObserver --irs-role=observer >"$logs/observer" 2>&1
wait "${pids[1]}"
grep -q IRS_OBSERVER_PASS "$logs/observer"
grep -q IRS_DRIVER_PASS "$logs/driver"
if grep -E 'SCRIPT ERROR|ERROR:' "$logs"/*; then exit 1; fi
printf 'IRS real-peer checks passed. Logs: %s\n' "$logs"
