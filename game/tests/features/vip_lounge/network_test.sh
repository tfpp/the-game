#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/vip_lounge/vip_probe.tscn
port=${VIP_TEST_PORT:-17903}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" >"$logs/server" 2>&1 &
pids+=("$!")
for ((i=0; i<150; i++)); do
  if rg -q 'Server listening' "$logs/server"; then break; fi
  sleep 0.1
done
rg -q 'Server listening' "$logs/server" || { cat "$logs/server"; exit 1; }
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=VipDriver --vip-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<150; i++)); do
  if rg -q VIP_READY "$logs/driver"; then break; fi
  sleep 0.1
done
rg -q VIP_READY "$logs/driver" || { cat "$logs/server" "$logs/driver"; exit 1; }
timeout 35 godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=VipObserver --vip-role=observer >"$logs/observer" 2>&1
wait "${pids[1]}"
for marker in VIP_LATE_JOIN_PASS VIP_SHARED_DRINK_PASS VIP_DISCONNECT_PASS; do
  rg -q "$marker" "$logs/observer" || { cat "$logs/observer"; exit 1; }
done
rg -q VIP_DRIVER_PASS "$logs/driver"
if rg 'SCRIPT ERROR|ERROR:' "$logs"; then exit 1; fi
printf 'VIP real-peer checks passed. Logs: %s\n' "$logs"
