#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/bar_companion/celeste_network_probe.tscn
port=${CELESTE_TEST_PORT:-17882}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=CelesteDriver --celeste-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<200; i++)); do
  if rg -q CELESTE_RECRUITED "$logs/driver"; then break; fi
  sleep 0.1
done
rg -q CELESTE_RECRUITED "$logs/driver" || { cat "$logs/driver"; exit 1; }
timeout 25 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=CelesteObserver --celeste-role=observer >"$logs/observer" 2>&1
wait "${pids[1]}"
for marker in CELESTE_LATE_JOIN_PASS CELESTE_DISCONNECT_PASS; do
  rg -q "$marker" "$logs/observer" || { cat "$logs/observer"; exit 1; }
done
rg -q CELESTE_DRIVER_PASS "$logs/driver"
if rg 'SCRIPT ERROR|ERROR:' "$logs"; then exit 1; fi
printf 'Celeste real-peer checks passed. Logs: %s\n' "$logs"
