#!/usr/bin/env bash
# Dedicated server, two clients, and rejected authentication/version probes.
set -euo pipefail
exec python3 "$(dirname "$0")/net_smoke.py"
