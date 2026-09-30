#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
logs=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
scene=res://tests/features/slot_machine/network_probe.tscn
port=${SLOT_TEST_PORT:-17885}
godot --headless "$scene" -- --server --dev-insecure-auth --port="$port" --slot-force-win >"$logs/server" 2>&1 &
pids+=("$!")
sleep 2
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=SlotObserver --slot-role=observer >"$logs/observer" 2>&1 &
pids+=("$!")
godot --headless "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=SlotDriver --slot-role=driver >"$logs/driver" 2>&1 &
pids+=("$!")
for ((i=0; i<450; i++)); do
  if grep -q DRIVER_DONE "$logs/driver"; then break; fi
  if grep -qE 'SCRIPT ERROR|ERROR:' "$logs/driver"; then break; fi
  sleep 0.1
done
grep -q DRIVER_DONE "$logs/driver" || { tail -80 "$logs/driver"; exit 1; }
[[ $(grep -c PAYOUT_REVEAL_PASS "$logs/driver") == 5 ]]
grep -q RANGE_REJECTED "$logs/driver"
grep -q COMPETING_REQUEST "$logs/observer"
grep -q 'SLOT_AUDIO 5' "$logs/observer"
# A third connection after the result gets the snapshot, never an old win show.
timeout 10 godot --headless --quit-after 120 "$scene" -- --connect="ws://127.0.0.1:$port" --dev-insecure-auth --name=SlotLate >"$logs/late" 2>&1
grep -q '"spin":5' "$logs/late"
if grep -q SLOT_AUDIO "$logs/late"; then tail -80 "$logs/late"; exit 1; fi
if grep -E 'SCRIPT ERROR|ERROR:' "$logs"/*; then exit 1; fi
printf 'Slot real-peer payout and late-join checks passed. Logs: %s\n' "$logs"
