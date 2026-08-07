#!/usr/bin/env bash
# Night shift — scheduler entry point (cycle D). Nightly, unattended: triages
# failing checks on the agent fleet's own (<branchPrefix>/*) open PRs.
# Non-blocking; checks the triage:paused kill switch and only invokes Claude
# when there is failing work. Durable spec: docs/night-shift.md in the target.
#
# Machine-local settings live in ~/.build-system/<repo-name>.env (created by
# the installer). Required there: BS_REPO (owner/name).
set -euo pipefail

# launchd/cron start jobs with a minimal PATH; append (don't prepend) the tool
# dirs so an existing gh on PATH — e.g. a test stub — still wins.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

SOURCE_DEFAULT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$HOME/.build-system/$(basename "$SOURCE_DEFAULT").env"
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE not found — create it (the installer writes a template)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$ENV_FILE"

REPO="${BS_REPO:?BS_REPO (owner/name) must be set in $ENV_FILE}"
SOURCE="${BS_SOURCE:-$SOURCE_DEFAULT}"
WORKTREE="${BS_TRIAGE_WORKTREE:-$HOME/.build-system/$(basename "$SOURCE")/night-shift-worktree}"
LOG_DIR="${BS_LOG_DIR:-$SOURCE/docs/ops/agent-logs}"
DEFAULT_BRANCH="${BS_DEFAULT_BRANCH:-main}"
ALLOWED_TOOLS="${BS_ALLOWED_TOOLS:-Bash(git*),Bash(gh*),Bash(node*),Edit,Write,Read}"
HELPER="${BS_TRIAGE_HELPER:-$(dirname "$0")/failing-agent-prs.cjs}"

# The fleet's branch prefix is repo config, not machine config, so it comes from
# the manifest rather than this script's env file. Fall back to the default when
# jq, the manifest, or the value is missing: a narrow wrong prefix idles the
# night shift, which is recoverable, while a blank one would match every branch.
BRANCH_PREFIX="claude"
if command -v jq >/dev/null 2>&1 && [ -f "$SOURCE/.build-system.json" ]; then
  from_manifest="$(jq -r '.config.branchPrefix // empty' "$SOURCE/.build-system.json" 2>/dev/null || true)"
  case "$from_manifest" in
    ""|REPLACE:*) ;;
    *) BRANCH_PREFIX="$from_manifest" ;;
  esac
fi

MODE="run"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --check)   MODE="check" ;;
    "")        ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

gh_fail_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$LOG_DIR/gh-errors.log" 2>/dev/null || true
}

# 1. Kill switch.
paused=0
if out=$(gh issue list --repo "$REPO" --label "triage:paused" --state open --json number --jq 'length' 2>/dev/null); then
  paused="$out"
else
  gh_fail_log "issue list triage:paused failed"
fi
if [ "$paused" != "0" ]; then
  echo "PAUSED: triage:paused is set — exiting."
  exit 0
fi

# 2. Work check — failing agent PRs from a trusted origin (provenance +
# failing-check filtering live in the tested helper). Fetch headRepositoryOwner /
# isCrossRepository so fork PRs — whose head branch name is attacker-controlled —
# are told apart from the fleet's own same-repo branches, and pass the base-repo
# owner plus the configured branch prefix so the helper can confirm same-repo
# provenance and recognize this repo's fleet branches.
REPO_OWNER="${REPO%%/*}"
prs_json='[]'
if out=$(gh pr list --repo "$REPO" --state open --json number,headRefName,headRepositoryOwner,isCrossRepository,statusCheckRollup 2>/dev/null); then
  prs_json="$out"
else
  gh_fail_log "pr list failed"
fi
failing="$(printf '%s' "$prs_json" \
  | BS_TRIAGE_REPO_OWNER="$REPO_OWNER" BS_TRIAGE_BRANCH_PREFIX="$BRANCH_PREFIX" node "$HELPER" 2>/dev/null || echo 0)"
if [ "$failing" = "0" ]; then
  echo "NO_WORK: no failing agent PRs — exiting."
  exit 0
fi
echo "WORK: failing agent PRs=$failing"

if [ "$MODE" = "check" ]; then exit 0; fi
if [ "$MODE" = "dry-run" ]; then
  echo "DRYRUN: would run 'claude -p /triage-prs' in $WORKTREE"
  exit 0
fi

# 3. Isolation — dedicated worktree off the latest default branch.
mkdir -p "$(dirname "$WORKTREE")" "$LOG_DIR"
git -C "$SOURCE" fetch origin "$DEFAULT_BRANCH" --quiet
if git -C "$SOURCE" worktree list --porcelain | grep -q "^worktree $WORKTREE$"; then
  git -C "$WORKTREE" reset --hard "origin/$DEFAULT_BRANCH"
else
  git -C "$SOURCE" worktree add --force "$WORKTREE" "origin/$DEFAULT_BRANCH"
fi

# 4. Invoke the night shift with a scoped tool allow-list. 5. Log.
run_id="night-shift-$(git -C "$SOURCE" rev-parse --short "origin/$DEFAULT_BRANCH")-$$"
echo "RUN: $run_id"
(
  cd "$WORKTREE" &&
  claude -p "/triage-prs" \
    --allowedTools "$ALLOWED_TOOLS"
) 2>&1 | tee "$LOG_DIR/$run_id.log"
