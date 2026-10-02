#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/bar_companion/busboy_network_probe.tscn
port=${BUSBOY_TEST_PORT:-17883}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
timeout 30 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=BusboyDriver --busboy-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<180; i++)); do
  if grep -q BUSBOY_CARGO_READY "$logs/driver"; then break; fi
  sleep 0.1
done
grep -q BUSBOY_CARGO_READY "$logs/driver" || { tail -80 "$logs/driver"; exit 1; }
timeout 25 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=BusboyObserver --busboy-role=observer >"$logs/observer" 2>&1
wait "${pids[1]}"
for marker in BUSBOY_LATE_JOIN_PASS BUSBOY_DISCONNECT_PASS; do
  grep -q "$marker" "$logs/observer" || { tail -80 "$logs/observer"; exit 1; }
done
grep -q BUSBOY_DRIVER_PASS "$logs/driver"
if grep -rE 'SCRIPT ERROR|ERROR:' "$logs"; then exit 1; fi
printf 'Busboy real-peer checks passed. Logs: %s\n' "$logs"
