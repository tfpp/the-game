#!/usr/bin/env bash
# Prepare an isolated pi agent directory on an ephemeral Actions runner.
# Never print the secrets, and keep PI_CODING_AGENT_DIR outside the checkout and artifacts.
#
# Env:
#   PI_CODING_AGENT_DIR      required; a temporary directory outside the checkout
#   CLAUDE_CODE_OAUTH_TOKEN  `claude setup-token` token; enables the anthropic-omp provider.
#                            The caller exports it to pi as ANTHROPIC_OAUTH_TOKEN, which
#                            the extension's backend reads when its own store is empty
#   CODEX_AUTH_JSON          Codex ChatGPT auth.json; enables openai-codex (the default
#                            model, imagegen and web search)
#   OPENROUTER_API_KEY       enables the openrouter provider; pi reads it from the env, so
#                            it is only checked here, never written
#   PI_WEB_ACCESS            npm spec of the web-access package (pinned default below)
#
# Installs harness/pi/extensions (anthropic-omp, image-generation) and pi-web-access into
# the agent directory and writes auth.json and settings.json there. Needs pi and bun on PATH.
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$0")/lib.sh"

: "${PI_CODING_AGENT_DIR:?Set PI_CODING_AGENT_DIR to a temporary directory outside the checkout}"
web_access="${PI_WEB_ACCESS:-npm:pi-web-access@0.34.0}"
# Non-secret marker the anthropic-omp extension expects in pi's auth.json (src/adapter.ts).
omp_marker="omp-managed-oauth-v1"

umask 077
mkdir -p "$PI_CODING_AGENT_DIR"
dir="$(cd "$PI_CODING_AGENT_DIR" && pwd)"
case "$dir/" in "$REPO_ROOT"/*) die "PI_CODING_AGENT_DIR must be outside the repo" ;; esac
chmod 700 "$dir"

# jwt_claims TOKEN -> the decoded payload JSON, or nothing.
jwt_claims() {
  local p
  p="$(cut -d. -f2 <<<"$1" | tr '_-' '/+')"
  while ((${#p} % 4)); do p+='='; done
  base64 -d <<<"$p" 2>/dev/null || true
}

auth='{}'
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  [[ "$CLAUDE_CODE_OAUTH_TOKEN" == sk-ant-oat* ]] ||
    die 'CLAUDE_CODE_OAUTH_TOKEN must be a `claude setup-token` OAuth token (sk-ant-oat…).'
  # The real token never enters auth.json; the extension's backend reads it from the env.
  auth="$(jq -c --arg m "$omp_marker" \
    '.["anthropic-omp"] = {type: "oauth", access: $m, refresh: $m, expires: 9007199254740991}' <<<"$auth")"
fi
if [[ -n "${CODEX_AUTH_JSON:-}" ]]; then
  jq -e 'type == "object" and (.tokens | type == "object") and
    (.tokens.access_token | type == "string" and length > 0) and
    (.tokens.refresh_token | type == "string" and length > 0)' \
    <<<"$CODEX_AUTH_JSON" >/dev/null 2>&1 ||
    die 'CODEX_AUTH_JSON must contain a Codex ChatGPT auth.json login.'
  access="$(jq -r .tokens.access_token <<<"$CODEX_AUTH_JSON")"
  claims="$(jwt_claims "$access")"
  jq -e 'type == "object"' <<<"$claims" >/dev/null 2>&1 || claims='{}'
  # An unknown expiry makes pi refresh before first use.
  expires="$(jq '(.exp // 0) * 1000 | floor' <<<"$claims")"
  account="$(jq -r '.tokens.account_id // empty' <<<"$CODEX_AUTH_JSON")"
  [[ -n "$account" ]] ||
    account="$(jq -r '.["https://api.openai.com/auth"].chatgpt_account_id // empty' <<<"$claims")"
  [[ -n "$account" ]] || die 'CODEX_AUTH_JSON has no ChatGPT account id.'
  auth="$(jq -c --argjson codex "$CODEX_AUTH_JSON" --argjson expires "$expires" --arg account "$account" \
    '.["openai-codex"] = {type: "oauth", access: $codex.tokens.access_token,
      refresh: $codex.tokens.refresh_token, expires: $expires, accountId: $account}' <<<"$auth")"
fi
if [[ -n "${OPENROUTER_API_KEY:-}" && "$OPENROUTER_API_KEY" =~ [[:space:]] ]]; then
  die 'OPENROUTER_API_KEY must be a single-line API key.'
fi
[[ "$auth" != '{}' || -n "${OPENROUTER_API_KEY:-}" ]] ||
  die 'Pi needs CODEX_AUTH_JSON, CLAUDE_CODE_OAUTH_TOKEN or OPENROUTER_API_KEY; see harness/README.md.'
printf '%s\n' "$auth" >"$dir/auth.json"
chmod 600 "$dir/auth.json"

# run.sh passes the same per-model level with --thinking; keep pi's own settings in step.
jq -n --slurpfile levels "$HARNESS_DIR/pi/thinking-levels.json" \
  '{defaultProvider: "openai-codex", defaultModel: "gpt-6.1-sol", defaultThinkingLevel: "medium",
    modelThinkingLevels: $levels[0], quietStartup: true, packages: []}' >"$dir/settings.json"

mkdir -p "$dir/extensions"
cp -R "$HARNESS_DIR/pi/extensions/." "$dir/extensions/"
omp="$dir/extensions/anthropic-omp"
log "installing the anthropic-omp runtime"
(cd "$omp/runtime" && bun install --frozen-lockfile --ignore-scripts) >&2
bun "$omp/scripts/link-native.ts" >&2
log "installing $web_access"
pi install "$web_access" >&2
