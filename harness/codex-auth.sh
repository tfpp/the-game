#!/usr/bin/env bash
# Restore a ChatGPT subscription login on an ephemeral Actions runner.
# Never print the secret, and keep CODEX_HOME outside the checkout and artifacts.
set -euo pipefail
: "${CODEX_HOME:?Set CODEX_HOME to a temporary directory outside the checkout}"
if [[ -z "${CODEX_AUTH_JSON:-}" ]]; then
  echo 'Missing CODEX_AUTH_JSON secret; see harness/README.md.' >&2
  exit 1
fi
if ! jq -e 'type == "object" and
  (.auth_mode == "chatgpt" or .auth_mode == null) and
  (.tokens | type == "object") and
  (.tokens.access_token | type == "string" and length > 0) and
  (.tokens.refresh_token | type == "string" and length > 0) and
  (.tokens.id_token | type == "string" and length > 0)' \
  <<<"$CODEX_AUTH_JSON" >/dev/null 2>&1; then
  echo 'CODEX_AUTH_JSON must contain a Codex ChatGPT auth.json login.' >&2
  exit 1
fi
umask 077
mkdir -p "$CODEX_HOME"
chmod 700 "$CODEX_HOME"
printf '%s\n' "$CODEX_AUTH_JSON" >"$CODEX_HOME/auth.json"
chmod 600 "$CODEX_HOME/auth.json"
# Force file-backed auth, avoiding any runner keyring or API-key login.
printf 'cli_auth_credentials_store = "file"\nforced_login_method = "chatgpt"\n' >"$CODEX_HOME/config.toml"
