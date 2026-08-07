#!/usr/bin/env bash
# Builder — scheduler entry point (cycle B: Builder + Gate 1).
# Non-blocking: pre-checks cheaply and invokes the builder only when there is
# work, so most scheduled wake-ups cost zero Claude tokens. Labels are the
# durable state across runs.
#
# Machine-local settings live in ~/.build-system/<repo-name>.env (created by
# the installer). Required there: BS_REPO (owner/name). Everything else has
# defaults derived from this script's location inside the target repo.
set -euo pipefail

# launchd/cron start jobs with a minimal PATH, so the toolchain (gh/git in
# Homebrew, node/claude in ~/.local/bin) isn't found and gh silently fails the
# pre-check. Append (don't prepend) the tool dirs so an existing gh on PATH —
# e.g. a test stub — still wins.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

# This script installs to <repo>/scripts/build-system/builder-run.sh.
SOURCE_DEFAULT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$HOME/.build-system/$(basename "$SOURCE_DEFAULT").env"
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found — create it (the installer writes a template)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$ENV_FILE"

REPO="${BS_REPO:?BS_REPO (owner/name) must be set in $ENV_FILE}"
SOURCE="${BS_SOURCE:-$SOURCE_DEFAULT}"
WORKTREE="${BS_WORKTREE:-$HOME/.build-system/$(basename "$SOURCE")/builder-worktree}"
LOG_DIR="${BS_LOG_DIR:-$SOURCE/docs/ops/agent-logs}"
DEFAULT_BRANCH="${BS_DEFAULT_BRANCH:-main}"
ALLOWED_TOOLS="${BS_ALLOWED_TOOLS:-Bash(git*),Bash(gh*),Edit,Write,Read}"
TOKENS_HELPER="${BS_TOKENS_HELPER:-$(dirname "$0")/extract-run-tokens.cjs}"

MODE="run"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --check)   MODE="check" ;;
    "")        ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# Count open issues carrying a label. Fail-safe to 0 so a gh hiccup never makes
# the pre-check think there is work (and burn a Claude run) — it just idles.
# A failure is logged (not silently swallowed) so a persistent gh/auth outage is
# discoverable rather than an invisible permanent idle.
count() {
  local out
  if out=$(gh issue list --repo "$REPO" --label "$1" --state open --json number --jq 'length' 2>/dev/null); then
    printf '%s\n' "$out"
  else
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    printf '%s gh count failed for label %q\n' "$(date -u +%FT%TZ)" "$1" >> "$LOG_DIR/gh-errors.log" 2>/dev/null || true
    echo 0
  fi
}

# 1. Kill switch — checked first, before any work is considered.
if [ "$(count "builder:paused")" != "0" ]; then
  echo "PAUSED: builder:paused is set — exiting."
  exit 0
fi

# 2. Cheap work check. plan:revise is included so a human /revise request on a
#    pending plan actually wakes the builder (label counts can't see comments,
#    so "request changes" is a label swap: plan:pending -> plan:revise).
to_plan="$(count "ready-for-agent")"
to_build="$(count "plan:approved")"
to_revise="$(count "plan:revise")"
if [ "$to_plan" = "0" ] && [ "$to_build" = "0" ] && [ "$to_revise" = "0" ]; then
  echo "NO_WORK: no ready-for-agent, plan:approved, or plan:revise issues — exiting."
  exit 0
fi
echo "WORK: ready-for-agent=$to_plan plan:approved=$to_build plan:revise=$to_revise"

if [ "$MODE" = "check" ]; then exit 0; fi
if [ "$MODE" = "dry-run" ]; then
  echo "DRYRUN: would run 'claude -p /build-next' in $WORKTREE"
  exit 0
fi

# 3. Isolation — refresh a dedicated worktree off the latest default branch so
#    the builder never touches the user's active checkout or uncommitted work.
mkdir -p "$(dirname "$WORKTREE")" "$LOG_DIR"
git -C "$SOURCE" fetch origin "$DEFAULT_BRANCH" --quiet
if git -C "$SOURCE" worktree list --porcelain | grep -q "^worktree $WORKTREE$"; then
  git -C "$WORKTREE" reset --hard "origin/$DEFAULT_BRANCH"
else
  git -C "$SOURCE" worktree add --force "$WORKTREE" "origin/$DEFAULT_BRANCH"
fi

# 4. Invoke the builder with a scoped tool allow-list (never the full
#    --dangerously-skip-permissions). --output-format json so the run's token
#    usage + OPENED_PR can be recorded.
# 5. Log the run for audit (JSON to the run log, stderr alongside).
run_id="builder-$(git -C "$SOURCE" rev-parse --short "origin/$DEFAULT_BRANCH")-$$"
run_log="$LOG_DIR/$run_id.json"
echo "RUN: $run_id"
(
  cd "$WORKTREE" &&
  claude -p "/build-next" --output-format json \
    --allowedTools "$ALLOWED_TOOLS"
) > "$run_log" 2> "$run_log.err" || true

# 6. Record the run's token cost against the PR it opened (best-effort; a
#    failure here never fails the run). The builder ends its output with
#    OPENED_PR=<n>; the helper pairs it with the usage total. Optional: only
#    runs when the helper is present and node is available.
if [ -f "$TOKENS_HELPER" ] && command -v node >/dev/null 2>&1; then
  read -r tokens pr < <(node "$TOKENS_HELPER" < "$run_log" 2>/dev/null || echo "0 none")
  if [ "$pr" != "none" ] && [ "$tokens" != "0" ]; then
    gh pr comment "$pr" --repo "$REPO" --body "<!-- build-system-tokens tokens=$tokens -->" 2>/dev/null \
      && echo "RECORDED: $tokens tokens on PR #$pr" \
      || echo "WARN: could not post token marker on PR #$pr"
  fi
fi
