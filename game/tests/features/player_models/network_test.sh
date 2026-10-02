#!/usr/bin/env bash
# Real authenticated server, driver and late observer; no Python dependency.
set -euo pipefail
game="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp="$(mktemp -d)"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$tmp"
}
trap cleanup EXIT
fail() {
  tail -n 80 "$tmp"/*.log
  exit 1
}
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
for emote in flip_off wave salute cheer; do
  rm -f "$tmp"/*.log "$tmp/stop" "$tmp/stop.pause"
  pids=()
  port="$((22000 + RANDOM % 20000))"
  spawn() {
    local role="$1" name="$1"
    if [[ "$role" == driver && "$emote" =~ ^(flip_off|salute)$ ]]; then name=Sor; fi
    local args=("--connect=ws://127.0.0.1:$port")
    if [[ "$role" == server ]]; then args=(--server "--port=$port"); fi
    touch "$tmp/$role.log"
    godot --headless --path "$game" res://tests/features/player_models/network_probe.tscn -- \
      --dev-insecure-auth "--avatar-role=$role" "--probe-stop=$tmp/stop" "--name=$name" \
      --emote-probe "--emote-name=$emote" "${args[@]}" > "$tmp/$role.log" 2>&1 &
    pids+=("$!")
  }
  spawn server
  wait_for "$tmp/server.log" 'Server listening'
  spawn driver
  wait_for "$tmp/driver.log" AVATAR_DRIVER_PASS
  wait_for "$tmp/server.log" AVATAR_OBSERVED
  spawn late
  wait_for "$tmp/late.log" AVATAR_OBSERVED
  for role in server driver late; do
    wait_for "$tmp/$role.log" EMOTE_OBSERVED
    wait_for "$tmp/$role.log" EMOTE_FINISHED
  done
  touch "$tmp/stop.pause"
  for role in server driver late; do wait_for "$tmp/$role.log" AVATAR_PAUSED; done
  touch "$tmp/stop"
  for pid in "${pids[@]}"; do wait "$pid" || fail; done
  if grep -q 'ERROR:' "$tmp"/*.log; then fail; fi
  pids=()
  echo "PASS: $emote identity, validation, cooldown, late-join phase and expiry"
done
