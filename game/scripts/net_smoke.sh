#!/usr/bin/env bash
# Dedicated server, two clients, and rejected authentication/version probes.
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${GODOT:-godot}" --headless -s scripts/network_checks.gd -- smoke
