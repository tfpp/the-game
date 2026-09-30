#!/usr/bin/env bash
# Tests for harness/pi-setup.sh with fake pi and bun, so nothing is installed.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
for cli in pi bun; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >>"%s/calls"\n' "$cli" "$work" >"$work/bin/$cli"
  chmod +x "$work/bin/$cli"
done
export PATH="$work/bin:$PATH"
unset CLAUDE_CODE_OAUTH_TOKEN CODEX_AUTH_JSON PI_WEB_ACCESS
export PI_CODING_AGENT_DIR="$work/agent"
auth="$PI_CODING_AGENT_DIR/auth.json"

# Explicit failures: errexit ignores `! cmd`, and bash 3.2 also ignores a failing `[[`.
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
expect_eq() { [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"; }
no_secret() { if grep -q 'secret-marker' "$@"; then fail "secret printed or stored in $*"; fi; }
called() { grep -qxF "$1" "$work/calls" || fail "not called: $1"; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
b64url() { printf '%s' "$1" | base64 | tr -d '=\n' | tr '/+' '_-'; }
jwt="x.$(b64url '{"exp":1800000000,"https://api.openai.com/auth":{"chatgpt_account_id":"acct-jwt"}}').sig"

reject() { # reject NAME: pi-setup.sh must fail without writing or printing a secret
  rm -rf "$PI_CODING_AGENT_DIR"
  if "$root/harness/pi-setup.sh" >"$work/log" 2>&1; then fail "expected failure: $1"; fi
  [[ ! -e "$auth" ]] || fail "$1: wrote auth.json"
  no_secret "$work/log"
}
reject 'no credentials'
CLAUDE_CODE_OAUTH_TOKEN='secret-marker' reject 'API key instead of an OAuth token'
CODEX_AUTH_JSON='secret-marker invalid json' reject 'invalid Codex JSON'
CODEX_AUTH_JSON='{"tokens":{"access_token":"secret-marker"}}' reject 'Codex login without refresh token'
CODEX_AUTH_JSON='{"tokens":{"access_token":"secret-marker","refresh_token":"r"}}' \
  reject 'Codex login without an account id'
CLAUDE_CODE_OAUTH_TOKEN='sk-ant-oat01-secret-marker' PI_CODING_AGENT_DIR="$root/harness/.pi-test" \
  reject 'agent dir inside the checkout'
[[ ! -e "$root/harness/.pi-test/auth.json" ]] || fail 'wrote credentials inside the checkout'
rm -rf "$root/harness/.pi-test"

echo "- both logins: the Anthropic token stays out of auth.json; Codex is converted"
export CLAUDE_CODE_OAUTH_TOKEN='sk-ant-oat01-secret-marker'
export CODEX_AUTH_JSON="{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"$jwt\",\"refresh_token\":\"refresh\",\"id_token\":\"id\"}}"
rm -f "$work/calls"
"$root/harness/pi-setup.sh" >"$work/log" 2>&1 || fail "setup failed: $(cat "$work/log")"
no_secret "$work/log" "$auth"
expect_eq "$(jq -c '.["anthropic-omp"]' "$auth")" \
  '{"type":"oauth","access":"omp-managed-oauth-v1","refresh":"omp-managed-oauth-v1","expires":9007199254740991}' 'anthropic-omp marker'
expect_eq "$(jq -c '.["openai-codex"]' "$auth")" \
  "{\"type\":\"oauth\",\"access\":\"$jwt\",\"refresh\":\"refresh\",\"expires\":1800000000000,\"accountId\":\"acct-jwt\"}" 'openai-codex login'
expect_eq "$(jq -c '[.defaultProvider, .defaultModel, .defaultThinkingLevel]' "$PI_CODING_AGENT_DIR/settings.json")" '["openai-codex","gpt-6.1-sol","medium"]' 'default model'
expect_eq "$(mode "$PI_CODING_AGENT_DIR")" 700 'agent dir mode'
expect_eq "$(mode "$auth")" 600 'auth.json mode'
for ext in anthropic-omp image-generation; do
  [[ -f "$PI_CODING_AGENT_DIR/extensions/$ext/index.ts" ]] || fail "extension $ext not installed"
done
called 'bun install --frozen-lockfile --ignore-scripts'
called "bun $PI_CODING_AGENT_DIR/extensions/anthropic-omp/scripts/link-native.ts"
called 'pi install npm:pi-web-access@0.34.0'

echo "- Codex alone; auth.json's account_id wins over the JWT claim"
unset CLAUDE_CODE_OAUTH_TOKEN
CODEX_AUTH_JSON="$(jq -c '.tokens.account_id = "acct-file"' <<<"$CODEX_AUTH_JSON")"
rm -rf "$PI_CODING_AGENT_DIR"
"$root/harness/pi-setup.sh" >/dev/null 2>&1 || fail 'Codex-only setup failed'
expect_eq "$(jq -r '.["openai-codex"].accountId' "$auth")" acct-file 'account id from auth.json'
expect_eq "$(jq -r 'has("anthropic-omp")' "$auth")" false 'no Anthropic marker without a token'
echo 'pi setup tests passed'
