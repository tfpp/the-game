#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/holdables/consumable_network_probe.tscn
port=${CONSUMABLE_TEST_PORT:-17893}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
timeout 30 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=Consumer --consume-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<200; i++)); do
  if rg -q CONSUMABLE_STARTED "$logs/driver"; then break; fi
  sleep 0.05
done
rg -q CONSUMABLE_STARTED "$logs/driver" || { cat "$logs/driver"; exit 1; }
timeout 25 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=Observer --consume-role=observer >"$logs/observer" 2>&1 || { cat "$logs/observer"; exit 1; }
wait "${pids[1]}"
for marker in CONSUMABLE_LATE_PASS CONSUMABLE_DISCONNECT_PASS; do
  rg -q "$marker" "$logs/observer" || { cat "$logs/observer"; exit 1; }
done
rg -q CONSUMABLE_DRIVER_PASS "$logs/driver"
if rg 'SCRIPT ERROR|ERROR:' "$logs"; then exit 1; fi
printf 'Consumable real-peer checks passed. Logs: %s\n' "$logs"
