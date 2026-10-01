#!/usr/bin/env bash
# Authenticated driver and late joiner exercise portals and the actual garage elevator.
set -euo pipefail
game="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT
fail() { tail -n 60 "$tmp"/*.log; exit 1; }
wait_for() {
  local file="$1" marker="$2"
  for ((i=0; i<1800; i++)); do
    if grep -q 'ERROR:' "$tmp"/*.log; then fail; fi
    if grep -q "$marker" "$file"; then return; fi
    for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null || fail; done
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
  godot --headless --path "$game" res://tests/features/street_hotel/network_probe.tscn -- \
    --dev-insecure-auth "--hotel-role=$role" "--probe-stop=$tmp/stop" \
    "--name=$role" "${args[@]}" > "$tmp/$role.log" 2>&1 &
  pids+=("$!")
}
spawn server
wait_for "$tmp/server.log" 'Server listening'
spawn driver
wait_for "$tmp/driver.log" HOTEL_DRIVER_ENTERED
spawn late
wait_for "$tmp/late.log" HOTEL_LATE_PASS
touch "$tmp/stop.late"
wait_for "$tmp/driver.log" HOTEL_DRIVER_PASS
touch "$tmp/stop.pause"
for role in server driver late; do wait_for "$tmp/$role.log" HOTEL_PAUSED; done
touch "$tmp/stop"
for pid in "${pids[@]}"; do wait "$pid" || fail; done
if grep -q 'ERROR:' "$tmp"/*.log; then fail; fi
echo 'PASS: street hotel floor travel, gravity, shared doors, late join and unloading'
