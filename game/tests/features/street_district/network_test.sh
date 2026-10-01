#!/usr/bin/env bash
# Authenticated driver and late joiner exercise the same production teleport endpoints.
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
  for ((i=0; i<600; i++)); do
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
  godot --headless --path "$game" res://tests/features/street_district/network_probe.tscn -- \
    --dev-insecure-auth "--street-role=$role" "--probe-stop=$tmp/stop" \
    "--name=$role" "${args[@]}" > "$tmp/$role.log" 2>&1 &
  pids+=("$!")
}
spawn server
wait_for "$tmp/server.log" 'Server listening'
spawn driver
wait_for "$tmp/driver.log" STREET_DRIVER_ENTERED
wait_for "$tmp/server.log" STREET_SERVER_VISITOR
spawn late
wait_for "$tmp/late.log" STREET_LATE_PASS
touch "$tmp/stop.late"
wait_for "$tmp/driver.log" STREET_DRIVER_PASS
touch "$tmp/stop.pause"
for role in server driver late; do wait_for "$tmp/$role.log" STREET_PAUSED; done
touch "$tmp/stop"
for pid in "${pids[@]}"; do wait "$pid" || fail; done
if grep -q 'ERROR:' "$tmp"/*.log; then fail; fi
echo 'PASS: street teleports, range/identity checks, late join, floor preload and unloading'
