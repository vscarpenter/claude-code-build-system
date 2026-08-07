#!/usr/bin/env bash
# claude-code-build-system installer.
# Copies tier artifacts into a target repo and records what it installed in a
# manifest (.build-system.json) with content hashes, so upgrades can tell
# "safe to re-sync" from "locally adapted — keep". Bash 3.2 compatible (macOS
# default shell): no associative arrays, lookups go through jq.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SYSTEM_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
MANIFEST_NAME=".build-system.json"

TIER=""
TARGET="."
DRY_RUN=0
FORCE=0
UPGRADE=0

usage() {
  cat <<EOF
Usage:
  ./install.sh --tier <1|2|3> [--target <repo>] [--dry-run] [--force]
  ./install.sh --upgrade [--target <repo>] [--dry-run] [--force]

Tiers are cumulative: 2 includes 1, 3 includes 2.
  1  session   CLAUDE.md, .claude/ commands+hooks+agents, coding standards
  2  pipeline  issue contract, risk labels, pipeline workflows, agent commands
  3  ops       local drivers, night-shift spec, scheduler templates, hosted variant
EOF
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "$@"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tier)    TIER="${2:-}"; shift 2 ;;
    --target)  TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --upgrade) UPGRADE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ "$UPGRADE" = 1 ] || case "$TIER" in 1|2|3) ;; *) usage 2 ;; esac
[ -d "$TARGET" ] || die "target '$TARGET' is not a directory"
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "target '$TARGET' is not a git repository (the manifest and upgrade path rely on one)"
TARGET="$(cd "$TARGET" && pwd)"
MANIFEST="$TARGET/$MANIFEST_NAME"
command -v jq >/dev/null 2>&1 || die "jq is required"

file_hash() { shasum -a 256 "$1" | awk '{print $1}'; }

# Existing-manifest helpers. All fail soft to "" when there is no manifest.
manifest_valid() { [ -f "$MANIFEST" ] && jq -e . "$MANIFEST" >/dev/null 2>&1; }
manifest_field() { jq -r "$1 // empty" "$MANIFEST" 2>/dev/null || true; }
recorded_hash() {  # $1 = repo-relative path
  jq -r --arg p "$1" '.files[] | select(.path==$p) | .sha256' "$MANIFEST" 2>/dev/null || true
}

if [ -f "$MANIFEST" ] && ! manifest_valid; then
  die "manifest $MANIFEST is not valid JSON — fix or remove it, or reinstall with --tier N --force"
fi

# plan_files <tier>: emit "src<TAB>dest" (dest repo-relative) for one tier.
# Tier trees mirror the target layout, except tier-root metadata files the
# installer itself consumes (labels.json), tier 3's mapped layout, and tier 1's
# coding-standards.md, which is sourced from the canonical standards/ below.
plan_files() {
  local tierdir
  case "$1" in
    1) tierdir="$ROOT/tiers/1-session" ;;
    2) tierdir="$ROOT/tiers/2-pipeline" ;;
    3) tierdir="$ROOT/tiers/3-ops" ;;
  esac
  # Tier 1 stamps the canonical standards, so the repo carries exactly one copy
  # to edit rather than a tier-tree duplicate that could silently drift. Emitted
  # ahead of the tree walk on purpose: written as a trailing
  # `[ "$1" = 1 ] && printf`, a false test returns 1 and aborts the whole
  # install for tiers 2 and 3 under `set -e` + `pipefail`.
  if [ "$1" = 1 ]; then
    printf '%s\t%s\n' "$ROOT/standards/coding-standards.md" "coding-standards.md"
  fi
  [ -d "$tierdir" ] || return 0
  ( cd "$tierdir" && find . -type f | sed 's|^\./||' | sort ) | while read -r rel; do
    case "$1:$rel" in
      2:labels.json) continue ;;                       # installer input, not installed
      3:local/*)     printf '%s\t%s\n' "$tierdir/$rel" "scripts/build-system/${rel#local/}" ;;
      3:actions/*)   printf '%s\t%s\n' "$tierdir/$rel" ".github/workflows/${rel#actions/}" ;;
      3:docs/*)      printf '%s\t%s\n' "$tierdir/$rel" "$rel" ;;
      3:*)           continue ;;                       # tier 3 installs only mapped paths
      *)             printf '%s\t%s\n' "$tierdir/$rel" "$rel" ;;
    esac
  done
}

plan_all() { local n; for n in $(seq 1 "$1"); do plan_files "$n"; done; }

# ---------------------------------------------------------------- install ---
do_install() {
  local prev_version=""
  if manifest_valid; then
    prev_version="$(manifest_field .systemVersion)"
    if [ "$prev_version" != "$SYSTEM_VERSION" ] && [ "$UPGRADE" = 0 ]; then
      die "target has v$prev_version installed; run ./install.sh --upgrade instead"
    fi
  fi

  local installed tmp; tmp="$(mktemp)"
  plan_all "$TIER" | while IFS=$'\t' read -r src dest; do
    local abs="$TARGET/$dest" action
    if [ -e "$abs" ]; then
      local rec; rec="$(recorded_hash "$dest")"
      if [ -n "$rec" ]; then
        # Tracked file. Unmodified → refresh (no-op at same version).
        # Locally modified → keep (reinstall never clobbers adaptations).
        if [ "$(file_hash "$abs")" = "$rec" ] || [ "$FORCE" = 1 ]; then action="INSTALL"; else action="KEEP"; fi
      elif [ "$FORCE" = 1 ]; then
        action="INSTALL"
      else
        action="SKIP"
      fi
    else
      action="INSTALL"
    fi
    note "$action: $dest"
    if [ "$DRY_RUN" = 0 ]; then
      case "$action" in
        INSTALL) mkdir -p "$(dirname "$abs")"; cp "$src" "$abs" ;;
      esac
      case "$action" in
        INSTALL|KEEP) printf '%s\t%s\n' "$dest" "$(file_hash "$abs")" >> "$tmp" ;;
      esac
    fi
  done

  if [ "$DRY_RUN" = 1 ]; then
    note "DRY-RUN: nothing written"
    rm -f "$tmp"
    return 0
  fi

  write_manifest "$TIER" "$tmp"
  rm -f "$tmp"
  apply_labels
  write_ops_env
  note "Installed tier $TIER (v$SYSTEM_VERSION) into $TARGET"
  next_steps
}

# The installer is where "what do I do now?" actually gets asked, so it answers
# for the tier it just installed and nothing more. Each block is the short list
# of things the system cannot do for itself; docs/getting-started.md carries the
# full narrative. Printed last, after the per-file lines, so it is what remains
# on screen. Never printed for --dry-run: nothing was installed to follow up on.
next_steps() {
  note ""
  if [ "$UPGRADE" = 1 ]; then
    note "NEXT STEPS (upgrade)"
    note "  1. Review any KEEP lines above. Those files carry your local edits,"
    note "     so this version's changes to them did not land."
    note "  2. Read CHANGELOG.md for what moved in v$SYSTEM_VERSION."
    note "  3. Commit $MANIFEST_NAME and the re-synced files."
    return 0
  fi

  note "NEXT STEPS (tier $TIER)"
  case "$TIER" in
    1)
      note "  1. Set the Stop hook command in .claude/settings.json. It ships inert;"
      note "     replace \`true\` with your fast typecheck."
      note "  2. Rewrite CLAUDE.md for this project. It ships as a filled-in example."
      note "  3. Commit $MANIFEST_NAME and the installed files."
      note "  4. Open Claude Code and run the loop: /qspec, then /tdd, then /qcheck."
      ;;
    2)
      note "  1. Fill in \"config\" in $MANIFEST_NAME: verifyCommands, protectedPaths,"
      note "     and branchPrefix. The agents refuse to run while REPLACE: remains,"
      note "     and renaming branchPrefix later strands open PRs under the old name."
      note "  2. Set the Stop hook in .claude/settings.json and rewrite CLAUDE.md"
      note "     for this project (both ship from tier 1 as templates)."
      note "  3. Commit $MANIFEST_NAME and the installed files."
      note "  4. File a change with the issue form, then triage it in by swapping"
      note "     needs-triage -> ready-for-agent. The form does not apply it for you."
      note "  5. Run /build-next in Claude Code. Approve its plan at Gate 1 by"
      note "     swapping plan:pending -> plan:approved."
      ;;
    3)
      note "  1. Finish the tier 1 and 2 setup first: the \"config\" block in"
      note "     $MANIFEST_NAME, CLAUDE.md, and the .claude/settings.json Stop hook."
      note "  2. Set BS_REPO (owner/name) in $HOME/.build-system/$(basename "$TARGET").env"
      note "  3. Check the wiring without spending a token:"
      note "       bash scripts/build-system/builder-run.sh --check"
      note "  4. Open an issue titled \"Night Shift Control\" and pin it. It receives"
      note "     the nightly self-audit reports and carries the triage:paused switch."
      note "  5. Schedule the drivers. Copy a .plist.template from"
      note "     scripts/build-system/ to ~/Library/LaunchAgents/, replace"
      note "     {{REPO_PATH}}, then launchctl load it. On Linux, use cron."
      ;;
  esac
  note ""
  note "  Full walkthrough: docs/getting-started.md"
}

write_manifest() {  # $1 = tier, $2 = "path<TAB>sha" file
  local config
  if manifest_valid && [ -n "$(manifest_field .config.branchPrefix)" ]; then
    config="$(jq .config "$MANIFEST")"
  else
    config='{
      "verifyCommands": ["REPLACE: e.g. bun run test", "REPLACE: e.g. bun run lint"],
      "protectedPaths": ["REPLACE: e.g. deploy/**", "REPLACE: e.g. infra/**"],
      "branchPrefix": "claude"
    }'
  fi
  jq -Rn \
    --arg v "$SYSTEM_VERSION" \
    --argjson tier "$1" \
    --argjson config "$config" \
    '{schemaVersion: 1, systemVersion: $v, tier: $tier, config: $config,
      files: [inputs | select(length>0) | split("\t") | {path: .[0], sha256: .[1]}]}' \
    < "$2" > "$MANIFEST"
}

# Tier 2+ creates the label state machine. gh missing/unauthed is not fatal:
# the same commands are printed for the human to run.
apply_labels() {
  [ "$TIER" -ge 2 ] 2>/dev/null || return 0
  local labels="$ROOT/tiers/2-pipeline/labels.json"
  [ -f "$labels" ] || return 0
  local can_gh=0
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then can_gh=1; fi
  jq -r '.[] | [.name, .color, .description] | @tsv' "$labels" | \
  while IFS=$'\t' read -r name color desc; do
    if [ "$can_gh" = 1 ]; then
      ( cd "$TARGET" && gh label create "$name" --color "$color" --description "$desc" --force ) \
        || note "WARN: could not create label $name"
    else
      note "MANUAL: gh label create $name --color $color --description \"$desc\" --force"
    fi
  done
}

# Tier 3's local drivers read machine-local settings from an env file outside
# the repo. Write a commented template on first tier-3 install; never touch an
# existing one (it is the human's file).
write_ops_env() {
  [ "$TIER" -ge 3 ] 2>/dev/null || return 0
  local env_file="$HOME/.build-system/$(basename "$TARGET").env"
  [ -e "$env_file" ] && { note "KEEP: $env_file (exists)"; return 0; }
  mkdir -p "$(dirname "$env_file")"
  cat > "$env_file" <<EOF
# Machine-local settings for the build-system ops drivers (builder-run.sh,
# triage-run.sh). Sourced as bash. Only BS_REPO is required.
BS_REPO=""                       # REQUIRED: gh repo slug, e.g. owner/name
BS_SOURCE="$TARGET"              # local checkout the worktrees hang off
#BS_DEFAULT_BRANCH="main"
#BS_WORKTREE=""                  # builder worktree (default ~/.build-system/<repo>/builder-worktree)
#BS_TRIAGE_WORKTREE=""           # night-shift worktree
#BS_LOG_DIR=""                   # default <repo>/docs/ops/agent-logs
#BS_ALLOWED_TOOLS=""             # extra scoped tools for claude -p, comma-separated
EOF
  note "WROTE: $env_file (fill in BS_REPO)"
}

# ---------------------------------------------------------------- upgrade ---
# Upgrade is the install loop with the tier read from the manifest and the
# version guard lifted: tracked-and-unmodified files re-sync from source,
# tracked-but-locally-modified files are KEPT (--force overwrites), and the
# manifest is restamped at the repo's current VERSION.
do_upgrade() {
  manifest_valid || die "no valid manifest at $MANIFEST — nothing to upgrade (install with --tier N first)"
  TIER="$(manifest_field .tier)"
  case "$TIER" in 1|2|3) ;; *) die "manifest has invalid tier '$TIER'" ;; esac
  note "Upgrading tier $TIER install to v$SYSTEM_VERSION"
  do_install
}

if [ "$UPGRADE" = 1 ]; then do_upgrade; else do_install; fi
