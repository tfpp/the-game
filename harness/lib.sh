# Shared helpers for the harness scripts. Source it; don't run it.
# shellcheck shell=bash

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
export HARNESS_DIR REPO_ROOT

# Conventional Commits types accepted in PR titles and commit subjects.
CC_TITLE_RE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].{0,70}$'

log() { printf '[harness] %s\n' "$*" >&2; }
die() {
  log "error: $*"
  exit 1
}

# slugify "Add a Jump Pad!" -> add-a-jump-pad (max 40 chars, no trailing dash)
slugify() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//')"
  s="${s:0:40}"
  while [[ "$s" == *- ]]; do s="${s%-}"; done
  printf '%s' "${s:-feature}"
}

# branch_for_issue 12 "Add a jump pad" -> agent/12-add-a-jump-pad
branch_for_issue() { printf 'agent/%s-%s' "$1" "$(slugify "$2")"; }

# issue_from_branch agent/12-add-a-jump-pad -> 12 (fails for non-agent branches)
issue_from_branch() {
  [[ "$1" =~ ^agent/([0-9]+)- ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# Human-review paths, read from CODEOWNERS so there is one list.
protected_patterns() {
  local line
  while read -r line _; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "${line#/}"
  done <"$REPO_ROOT/.github/CODEOWNERS"
}

# Reads file paths on stdin and prints the ones under a protected pattern.
filter_protected() {
  local patterns f p
  patterns="$(protected_patterns)"
  while IFS= read -r f; do
    for p in $patterns; do
      if [[ "$p" == */ && "$f" == "$p"* ]] || [[ "$f" == "$p" || "$f" == "$p"/* ]]; then
        printf '%s\n' "$f"
        break
      fi
    done
  done
}

# jq definitions for an issue object. Issues opened by the Discord bot (author type Bot)
# end with a "Requested-by: <name> <discord:<id>>" trailer naming the Discord requester;
# a human-authored issue can't claim one.
#   requester     "@login", or "<name> on Discord"
#   request_body  the body without CRs or the trailer
# shellcheck disable=SC2016,SC2034
ISSUE_JQ='def body_lines: (.body // "" | gsub("\r"; "") | split("\n"));
def discord_requester: if .user.type == "Bot" then ([body_lines[] | select(startswith("Requested-by: ")) | ltrimstr("Requested-by: ")] | last) else null end;
def requester: discord_requester as $d | if $d then ($d | sub(" <discord:[0-9]+>$"; "")) + " on Discord" else "@" + .user.login end;
def request_body: if discord_requester then [body_lines[] | select(startswith("Requested-by: ") | not)] | join("\n") | sub("\\s+$"; "") else (.body // "" | gsub("\r"; "")) end;
'

# valid_title "feat(game): add jump pads" -> exit 0
valid_title() { [[ "$1" =~ $CC_TITLE_RE ]]; }

# worktree_id -> the tree hash of the working tree's content: tracked and untracked
# files, minus ignored ones, as `git add -A && git write-tree` would record it. Uses a
# scratch index, so the real index and staging are untouched.
worktree_id() {
  local index id
  index="$(mktemp)"
  cp "$(git rev-parse --git-path index)" "$index" 2>/dev/null || rm -f "$index"
  id="$(GIT_INDEX_FILE="$index" git add -A . && GIT_INDEX_FILE="$index" git write-tree)" || id=""
  rm -f "$index"
  [[ -n "$id" ]] && printf '%s' "$id"
}

# Where verify.sh records the last worktree_id it passed on (inside .git, never committed).
verified_stamp() { printf '%s/harness-verified' "$(git rev-parse --absolute-git-dir)"; }

# changed_paths -> files that differ from the merge base with $VERIFY_BASE (default
# origin/main), including uncommitted and untracked files. Fails when there is nothing
# to compare: no such base, or a clean checkout of the base itself.
changed_paths() {
  local base
  base="$(git merge-base HEAD "${VERIFY_BASE:-origin/main}" 2>/dev/null)" || return 1
  if [[ "$base" == "$(git rev-parse HEAD)" && -z "$(git status --porcelain)" ]]; then
    return 1
  fi
  { git diff --name-only "$base" && git ls-files --others --exclude-standard; } | sort -u
}
