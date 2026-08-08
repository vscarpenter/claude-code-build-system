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
    --tier)    [ $# -ge 2 ] || die "--tier requires a value"; TIER="$2"; shift 2 ;;
    --target)  [ $# -ge 2 ] || die "--target requires a value"; TARGET="$2"; shift 2 ;;
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
TARGET="$(cd "$TARGET" && pwd -P)"
GIT_TOPLEVEL="$(git -C "$TARGET" rev-parse --show-toplevel)"
GIT_TOPLEVEL="$(cd "$GIT_TOPLEVEL" && pwd -P)"
[ "$TARGET" = "$GIT_TOPLEVEL" ] \
  || die "target must be the repository root ($GIT_TOPLEVEL), not a subdirectory ($TARGET)"
MANIFEST="$TARGET/$MANIFEST_NAME"
command -v jq >/dev/null 2>&1 || die "jq is required"

file_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "shasum or sha256sum is required"
  fi
}

value_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    die "shasum or sha256sum is required"
  fi
}

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
      1:.claude/commands/*.md|2:.claude/commands/*.md)
        # Claude Code discovers the legacy command path. Codex, OpenCode, and
        # Copilot discover the same source as an Agent Skill. One source file
        # feeds both destinations so workflow semantics cannot drift by harness.
        printf '%s\t%s\n' "$tierdir/$rel" "$rel"
        local skill_name; skill_name="$(basename "$rel" .md)"
        printf '%s\t%s\n' "$tierdir/$rel" ".agents/skills/$skill_name/SKILL.md"
        ;;
      3:local/*)     printf '%s\t%s\n' "$tierdir/$rel" "scripts/build-system/${rel#local/}" ;;
      3:actions/*)   printf '%s\t%s\n' "$tierdir/$rel" ".github/workflows/${rel#actions/}" ;;
      3:docs/*)      printf '%s\t%s\n' "$tierdir/$rel" "$rel" ;;
      3:*)           continue ;;                       # tier 3 installs only mapped paths
      *)             printf '%s\t%s\n' "$tierdir/$rel" "$rel" ;;
    esac
  done
}

plan_all() {
  local n=1
  while [ "$n" -le "$1" ]; do plan_files "$n"; n=$((n + 1)); done
}

# Dynamic tree walking keeps the distribution easy to extend, but an absent
# control-plane artifact must not silently produce a successful, unusable
# install. This is the minimum executable inventory for each cumulative tier.
validate_source_payload() {
  local required path
  required="VERSION
standards/coding-standards.md
tiers/1-session/CLAUDE.md
tiers/1-session/AGENTS.md
tiers/1-session/.claude/settings.json
tiers/1-session/.claude/commands/qspec.md
tiers/1-session/.claude/commands/tdd.md
tiers/1-session/.claude/commands/qcheck.md
tiers/1-session/.claude/hooks/protect-files.sh"
  if [ "$TIER" -ge 2 ]; then
    required="$required
tiers/2-pipeline/labels.json
tiers/2-pipeline/.claude/commands/build-next.md
tiers/2-pipeline/.claude/commands/triage-prs.md
tiers/2-pipeline/.github/ISSUE_TEMPLATE/change_request.yml
tiers/2-pipeline/.github/workflows/apply-risk-label.yml
tiers/2-pipeline/scripts/parse-risk-tier.cjs
tiers/2-pipeline/scripts/build-system.cjs
tiers/2-pipeline/scripts/lib/protocol.cjs
tiers/2-pipeline/scripts/lib/policy.cjs
tiers/2-pipeline/scripts/lib/workspace.cjs
tiers/2-pipeline/scripts/lib/adapters.cjs
tiers/2-pipeline/scripts/lib/github.cjs
tiers/2-pipeline/scripts/lib/evidence.cjs
tiers/2-pipeline/scripts/lib/system.cjs
tiers/2-pipeline/scripts/schemas/agent-result.schema.json"
  fi
  if [ "$TIER" -ge 3 ]; then
    required="$required
tiers/3-ops/local/builder-run.sh
tiers/3-ops/local/triage-run.sh
tiers/3-ops/actions/actions-builder.yml"
  fi
  for path in $required; do
    [ -f "$ROOT/$path" ] || die "distribution is incomplete; required payload is missing: $path"
  done
}

# Refuse destinations that could escape through a symlink or collide with a
# non-directory ancestor. Payload paths are trusted distribution input, but
# target repositories are not: an existing `.claude -> /elsewhere` must never
# turn an ordinary install into an outside-repository write.
validate_destination() { # $1 = repo-relative destination
  local dest="$1" abs parent
  case "$dest" in
    ""|/*|..|../*|*/../*|*/..) die "unsafe install destination '$dest'" ;;
  esac
  abs="$TARGET/$dest"
  case "$abs" in "$TARGET"/*) ;; *) die "destination escapes target: $dest" ;; esac
  [ ! -L "$abs" ] || die "refusing symlink destination: $dest"
  parent="$(dirname "$abs")"
  while [ "$parent" != "$TARGET" ]; do
    [ ! -L "$parent" ] || die "refusing symlinked destination parent: ${parent#"$TARGET/"}"
    if [ -e "$parent" ] && [ ! -d "$parent" ]; then
      die "destination parent is not a directory: ${parent#"$TARGET/"}"
    fi
    parent="$(dirname "$parent")"
  done
}

preflight_plan() {
  plan_all "$TIER" | while IFS=$'\t' read -r _src dest; do
    validate_destination "$dest"
  done
}

# ---------------------------------------------------------------- install ---
do_install() {
  local prev_version="" prev_tier=""
  if manifest_valid; then
    prev_version="$(manifest_field .systemVersion)"
    prev_tier="$(manifest_field .tier)"
    if [ "$prev_version" != "$SYSTEM_VERSION" ] && [ "$UPGRADE" = 0 ]; then
      die "target has v$prev_version installed; run ./install.sh --upgrade instead"
    fi
    if [ "$UPGRADE" = 0 ] && [ -n "$prev_tier" ] && [ "$TIER" -lt "$prev_tier" ] 2>/dev/null; then
      die "target already has tier $prev_tier; refusing to downgrade its manifest to tier $TIER"
    fi
  fi

  # Validate the entire plan before the first write. This prevents predictable
  # path collisions from leaving a half-installed, untracked payload.
  validate_source_payload
  preflight_plan

  local tmp plan_file action_file stage_dir backup_dir created_file committed
  tmp="$(mktemp)"
  plan_file="$(mktemp)"
  action_file="$(mktemp)"
  stage_dir="$(mktemp -d)"
  backup_dir="$(mktemp -d)"
  created_file="$(mktemp)"
  committed=0
  plan_all "$TIER" > "$plan_file"

  rollback_install() {
    local dest abs
    [ "$committed" = 1 ] || {
      while IFS= read -r dest; do
        [ -n "$dest" ] || continue
        abs="$TARGET/$dest"
        if [ -e "$backup_dir/$dest" ] || [ -L "$backup_dir/$dest" ]; then
          mkdir -p "$(dirname "$abs")"
          cp -p "$backup_dir/$dest" "$abs" 2>/dev/null || true
        else
          rm -f "$abs" 2>/dev/null || true
        fi
      done < "$created_file"
      if [ -e "$backup_dir/$MANIFEST_NAME" ]; then
        cp -p "$backup_dir/$MANIFEST_NAME" "$MANIFEST" 2>/dev/null || true
      else
        rm -f "$MANIFEST" 2>/dev/null || true
      fi
    }
    rm -rf "$stage_dir" "$backup_dir"
    rm -f "$tmp" "$plan_file" "$action_file" "$created_file"
  }

  # Decide and stage every installer-owned byte before changing the target.
  # This catches read/disk errors while rollback is still trivial.
  while IFS=$'\t' read -r src dest; do
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
    printf '%s\t%s\t%s\n' "$action" "$src" "$dest" >> "$action_file"
    if [ "$DRY_RUN" = 0 ] && [ "$action" = "INSTALL" ]; then
      mkdir -p "$stage_dir/$(dirname "$dest")"
      cp -p "$src" "$stage_dir/$dest"
    fi
  done < "$plan_file"

  if [ "$DRY_RUN" = 1 ]; then
    note "DRY-RUN: nothing written"
    committed=1
    rollback_install
    return 0
  fi

  if [ -e "$MANIFEST" ]; then cp -p "$MANIFEST" "$backup_dir/$MANIFEST_NAME"; fi
  trap 'rollback_install' ERR INT TERM
  while IFS=$'\t' read -r action src dest; do
    local abs="$TARGET/$dest" rec
    case "$action" in
      INSTALL)
        validate_destination "$dest" # narrow the preflight/write race
        if [ -e "$abs" ] || [ -L "$abs" ]; then
          mkdir -p "$backup_dir/$(dirname "$dest")"
          cp -p "$abs" "$backup_dir/$dest"
        fi
        printf '%s\n' "$dest" >> "$created_file"
        mkdir -p "$(dirname "$abs")"
        cp -p "$stage_dir/$dest" "$abs"
        printf '%s\t%s\n' "$dest" "$(file_hash "$abs")" >> "$tmp"
        ;;
      KEEP)
        rec="$(recorded_hash "$dest")"
        printf '%s\t%s\n' "$dest" "$rec" >> "$tmp"
        ;;
    esac
  done < "$action_file"

  write_manifest "$TIER" "$tmp"
  committed=1
  trap - ERR INT TERM
  rollback_install
  apply_labels
  write_ops_runtime
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
      note "  5. Run node scripts/build-system.cjs doctor --harness all, then"
      note "     node scripts/build-system.cjs run --harness <claude|codex>."
      note "     Approve Gate 1 with: node scripts/build-system.cjs approve --issue N"
      ;;
    3)
      note "  1. Finish the tier 1 and 2 setup first: the \"config\" block in"
      note "     $MANIFEST_NAME, CLAUDE.md, and the .claude/settings.json Stop hook."
      note "  2. Review the RUNTIME CONFIG path printed above and select its harness."
      note "  3. Check the wiring without spending a token using the immutable"
      note "     builder-run.sh --config <runtime-config> --check command."
      note "  4. Open an issue titled \"Night Shift Control\" and pin it. It receives"
      note "     the nightly self-audit reports and carries the triage:paused switch."
      note "  5. Schedule the immutable drivers. Copy a .plist.template from"
      note "     scripts/build-system/ to ~/Library/LaunchAgents/, replace"
      note "     {{RUNTIME_PATH}} and {{RUNTIME_CONFIG}}, then launchctl load it."
      note "     On Linux, use the immutable paths in cron."
      ;;
  esac
  note ""
  note "  Full walkthrough: docs/getting-started.md"
}

write_manifest() {  # $1 = tier, $2 = "path<TAB>sha" file
  local config next_manifest
  if manifest_valid && [ -n "$(manifest_field .config.branchPrefix)" ]; then
    config="$(jq .config "$MANIFEST")"
  else
    config='{
      "repo": "REPLACE: owner/name",
      "defaultBranch": "main",
      "harness": "claude",
      "verifyCommands": ["REPLACE: e.g. bun run test", "REPLACE: e.g. bun run lint"],
      "protectedPaths": ["REPLACE: e.g. deploy/**", "REPLACE: e.g. infra/**"],
      "allowedPaths": ["**"],
      "requiredChecks": ["REPLACE: e.g. test"],
      "branchPrefix": "agent",
      "leaseMinutes": 90,
      "runTimeoutSeconds": 3600,
      "verifyTimeoutSeconds": 900,
      "maxChangedFiles": 100,
      "maxDiffBytes": 1048576,
      "dailyRunLimit": 20,
      "maxConsecutiveFailures": 3,
      "maxBudgetUsd": 10
    }'
  fi
  next_manifest="$(mktemp "$TARGET/.build-system.json.tmp.XXXXXX")"
  if ! jq -Rn \
    --arg v "$SYSTEM_VERSION" \
    --argjson tier "$1" \
    --argjson config "$config" \
    '{schemaVersion: 1, systemVersion: $v, tier: $tier, config: $config,
      files: [inputs | select(length>0) | split("\t") | {path: .[0], sha256: .[1]}]}' \
    < "$2" > "$next_manifest"; then
    rm -f "$next_manifest"
    die "could not write manifest"
  fi
  mv "$next_manifest" "$MANIFEST"
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

# Tier 3 schedules an immutable copy of the controller rather than executable
# code in a mutable checkout. Machine settings are JSON data, never sourced as
# shell. The canonical-path suffix prevents same-basename repository collisions.
write_ops_runtime() {
  [ "$TIER" -ge 3 ] 2>/dev/null || return 0
  local repo_id runtime runtime_parent runtime_stage config_dir config_file manifest_tmp rel
  repo_id="$(basename "$TARGET")-$(value_hash "$TARGET" | cut -c1-12)"
  runtime="$HOME/.local/libexec/claude-code-build-system/$SYSTEM_VERSION"
  runtime_parent="$(dirname "$runtime")"
  config_dir="$HOME/.build-system/repos/$repo_id"
  config_file="$config_dir/config.json"

  if [ ! -d "$runtime" ]; then
    mkdir -p "$runtime_parent"; chmod 700 "$HOME/.local/libexec/claude-code-build-system" "$runtime_parent" 2>/dev/null || true
    runtime_stage="$(mktemp -d "$runtime_parent/.${SYSTEM_VERSION}.tmp.XXXXXX")"
    if ! (
      mkdir -p "$runtime_stage/lib" "$runtime_stage/schemas"
      chmod 700 "$runtime_stage" "$runtime_stage/lib" "$runtime_stage/schemas"
      cp -p "$ROOT/tiers/3-ops/local/builder-run.sh" "$runtime_stage/builder-run.sh"
      cp -p "$ROOT/tiers/3-ops/local/triage-run.sh" "$runtime_stage/triage-run.sh"
      cp -p "$ROOT/tiers/2-pipeline/scripts/build-system.cjs" "$runtime_stage/build-system.cjs"
      cp -p "$ROOT/tiers/2-pipeline/scripts/lib/"*.cjs "$runtime_stage/lib/"
      cp -p "$ROOT/tiers/2-pipeline/scripts/schemas/"*.json "$runtime_stage/schemas/"
      chmod 700 "$runtime_stage/builder-run.sh" "$runtime_stage/triage-run.sh" "$runtime_stage/build-system.cjs"
      chmod 600 "$runtime_stage/lib/"*.cjs "$runtime_stage/schemas/"*.json
      manifest_tmp="$(mktemp)"
      ( cd "$runtime_stage" && find . -type f ! -name runtime-manifest.json | sed 's|^\./||' | sort ) | while read -r rel; do
        printf '%s\t%s\n' "$rel" "$(file_hash "$runtime_stage/$rel")"
      done > "$manifest_tmp"
      jq -Rn --arg version "$SYSTEM_VERSION" \
        '{schemaVersion:1,systemVersion:$version,files:[inputs|split("\t")|{path:.[0],sha256:.[1]}]}' \
        < "$manifest_tmp" > "$runtime_stage/runtime-manifest.json"
      rm -f "$manifest_tmp"
      chmod 600 "$runtime_stage/runtime-manifest.json"
    ); then
      rm -rf "$runtime_stage"
      die "could not stage immutable runtime"
    fi
    mv "$runtime_stage" "$runtime"
    note "WROTE: immutable runtime $runtime"
  else
    note "KEEP: immutable runtime $runtime"
  fi

  mkdir -p "$config_dir"; chmod 700 "$HOME/.build-system" "$HOME/.build-system/repos" "$config_dir" 2>/dev/null || true
  if [ ! -e "$config_file" ]; then
    jq -n --arg source "$TARGET" --arg runtime "$runtime" \
      '{schemaVersion:1,source:$source,harness:"claude",runtime:$runtime}' > "$config_file"
    chmod 600 "$config_file"
    note "WROTE: $config_file"
  else
    note "KEEP: $config_file (exists)"
  fi
  note "RUNTIME CONFIG: $config_file"
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
