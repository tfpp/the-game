#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export CODEX_HOME="$work/home"
export CODEX_AUTH_JSON=''
reject() {
  if "$root/harness/codex-auth.sh" >"$work/log" 2>&1; then
    echo 'Expected invalid credentials to fail' >&2
    exit 1
  fi
  [[ ! -e "$CODEX_HOME/auth.json" ]]
  ! grep -q 'secret-marker' "$work/log"
}
reject
CODEX_AUTH_JSON='secret-marker invalid json'
reject
CODEX_AUTH_JSON='{"OPENAI_API_KEY":"secret-marker"}'
reject
CODEX_AUTH_JSON='{"tokens":{"access_token":"secret-marker"}}'
reject
CODEX_AUTH_JSON='{"auth_mode":"chatgpt","tokens":{"access_token":"secret-marker","refresh_token":"refresh","id_token":"id"}}'
"$root/harness/codex-auth.sh" >"$work/log" 2>&1
[[ ! -s "$work/log" ]]
[[ "$(jq -r .tokens.access_token "$CODEX_HOME/auth.json")" == secret-marker ]]
grep -q 'cli_auth_credentials_store = "file"' "$CODEX_HOME/config.toml"
grep -q 'forced_login_method = "chatgpt"' "$CODEX_HOME/config.toml"
python3 - "$CODEX_HOME" <<'PY'
import pathlib
import stat
import sys
home = pathlib.Path(sys.argv[1])
assert stat.S_IMODE(home.stat().st_mode) == 0o700
assert stat.S_IMODE((home / 'auth.json').stat().st_mode) == 0o600
PY
# Older Codex login files omit auth_mode.
CODEX_AUTH_JSON="$(jq 'del(.auth_mode)' <<<"$CODEX_AUTH_JSON")"
"$root/harness/codex-auth.sh"
echo 'codex auth tests passed'
