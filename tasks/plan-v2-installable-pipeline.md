# claude-code-build-system v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve this repo into the installable, tiered issue → Claude → PR build system per `tasks/spec-v2-installable-pipeline.md`.

**Architecture:** A `tiers/` source tree mirrors target-repo layout per tier; `install.sh` copies cumulatively, stamps a sha256 manifest (`.build-system.json`), and upgrades via three-way hash comparison. Generalized pipeline artifacts read runtime config (verify commands, protected paths, branch prefix) from the manifest with `jq`.

**Tech Stack:** bash + coreutils + jq + git (gh optional). Plain-bash tests. GitHub Actions CI on ubuntu.

## Global Constraints

- Work on branch `feat/v2-installable-pipeline`; Conventional Commits with scope + `Claude-Session:` trailer (creating-git-commits skill); never push without explicit go-ahead.
- Installer/tests: bash only, no bats, no network (gh calls mockable via PATH shim).
- `grep -riE 'gsd|cloudfront|taskmanager' tiers/` must return nothing (spec AC8).
- Hard-limits block, night-shift invariants ("verify before submit", "fixes re-enter the gate"), and kill switches survive in substance (spec AC9).
- `global/` keeps its v1 path. Source repos are read-only.
- Manifest name: `.build-system.json`. Version: `2.0.0`. Env file: `~/.build-system/<repo-name>.env`.
- Spec source paths (read-only inputs) are listed in the spec's Inputs table; this plan references them as `GSD=~/Projects/gsd-taskmanager`, `BARO=~/Projects/Barometer`, `ABS=~/Projects/AI-Build-System`.

---

### Task 1: Test harness + CI + version scaffolding

**Files:**
- Create: `tests/run-tests.sh`, `VERSION` (`2.0.0`), `CHANGELOG.md`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `run_tests` harness with `assert_eq`, `assert_file`, `assert_no_file`, `assert_grep`, `fail`; each `test_*` function runs in a fresh `$TMPDIR` fixture via `make_target_repo` (git init + one commit). Later tasks append `test_*` functions to this file.

- [ ] Step 1: Write `tests/run-tests.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; CURRENT=""
fail() { echo "FAIL[$CURRENT]: $*"; FAIL=$((FAIL+1)); }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$1' got '$2' ${3:-}"; }
assert_file() { [ -f "$1" ] || fail "missing file $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected file $1"; }
assert_grep() { grep -qE "$2" "$1" || fail "pattern '$2' not in $1"; }
make_target_repo() {  # echoes path to a fresh git repo
  local d; d="$(mktemp -d)"; git -C "$d" init -q
  git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  echo "$d"
}
run_test() { CURRENT="$1"; local before=$FAIL; "$1"; [ $FAIL -eq $before ] && { PASS=$((PASS+1)); echo "ok $1"; }; }
test_harness_self_check() { assert_eq "a" "a"; }
main() {
  for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
  echo "passed=$PASS failed=$FAIL"; [ $FAIL -eq 0 ]
}
main
```

- [ ] Step 2: Run `bash tests/run-tests.sh` → expect `passed=1 failed=0`, exit 0.
- [ ] Step 3: Write `VERSION` (`2.0.0`), `CHANGELOG.md` (`## 2.0.0 — unreleased` + one-line summary), and `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]
permissions: { contents: read }
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get install -y jq
      - run: bash tests/run-tests.sh
```

- [ ] Step 4: Commit `chore(scaffold): add test harness, VERSION, CHANGELOG, CI`.

### Task 2: Restructure v1 content into tiers/1-session + standards/

**Files:**
- Create: `standards/coding-standards.md` (from `$ABS/coding-standards.md` + header), `tiers/1-session/` tree
- Modify: none deleted yet except `templates/`, `examples/` (git mv into tiers)

**Interfaces:**
- Produces: `tiers/1-session/` mirrors target layout exactly: `CLAUDE.md`, `.claude/settings.json`, `.claude/commands/{qspec,tdd,qcheck}.md`, `.claude/hooks/{format-edits,protect-files}.sh`, `.claude/agents/{a11y-reviewer,pg-migration-reviewer}.md`, `tasks/{lessons,todo}.md`, `coding-standards.md` (copy of standards/). Installer (Task 3) copies `tiers/N-*/` contents to target root verbatim.

- [ ] Step 1: `git mv` v1 files into `tiers/1-session/` at their target-relative paths: `templates/CLAUDE.md → tiers/1-session/CLAUDE.md`; `.claude/{settings.json,commands,hooks,agents} → tiers/1-session/.claude/...`; `templates/{lessons,todo}.md → tiers/1-session/tasks/`. Delete `templates/coding-standards.md`? No — `git mv templates/coding-standards.md tiers/1-session/docs/coding-standards-skeleton.md` (bring-your-own-standards skeleton). `git rm examples/coding-standards.md` (superseded by standards/).
- [ ] Step 2: Copy `$ABS/coding-standards.md` → `standards/coding-standards.md`, prepending:

```markdown
<!-- Distributed by claude-code-build-system v2.0.0 · standards v18.0 ·
     canonical source: standards/coding-standards.md in that repo.
     Upgrade with: ./install.sh --upgrade -->
```

Then `cp standards/coding-standards.md tiers/1-session/coding-standards.md`.
- [ ] Step 3: Add test to `tests/run-tests.sh`:

```bash
test_tier1_source_tree_complete() {
  for f in CLAUDE.md coding-standards.md .claude/settings.json \
    .claude/commands/qspec.md .claude/commands/tdd.md .claude/commands/qcheck.md \
    .claude/hooks/format-edits.sh .claude/hooks/protect-files.sh \
    tasks/lessons.md tasks/todo.md; do
    assert_file "$ROOT/tiers/1-session/$f"
  done
}
```

- [ ] Step 4: Run tests → pass. Commit `refactor(tiers): move session layer into tiers/1-session and add canonical standards`.

### Task 3: Installer core — tier 1, manifest, idempotency, dry-run, guards

**Files:**
- Create: `install.sh`
- Test: append to `tests/run-tests.sh`

**Interfaces:**
- Produces: `./install.sh --tier <1|2|3> [--target <path>] [--dry-run] [--force]`, `--upgrade` (Task 6). Manifest schema:

```json
{ "schemaVersion": 1, "systemVersion": "2.0.0", "tier": 1,
  "config": { "verifyCommands": ["REPLACE: e.g. bun run test"],
              "protectedPaths": ["REPLACE: e.g. deploy/**"],
              "branchPrefix": "claude" },
  "files": [ { "path": "CLAUDE.md", "sha256": "..." } ] }
```

Functions: `plan_files(tier)` (lists source→dest pairs), `file_hash(path)`, `write_manifest`, `install_file(src,dest)` (skip+warn if dest exists untracked, overwrite with `--force`).

- [ ] Step 1: Write failing tests first (append):

```bash
test_tier1_fresh_install_places_files_and_manifest() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  for f in CLAUDE.md coding-standards.md .claude/settings.json tasks/lessons.md; do assert_file "$t/$f"; done
  assert_file "$t/.build-system.json"
  assert_eq "2.0.0" "$(jq -r .systemVersion "$t/.build-system.json")"
  assert_eq "1" "$(jq -r .tier "$t/.build-system.json")"
  local h; h="$(jq -r '.files[]|select(.path=="CLAUDE.md").sha256' "$t/.build-system.json")"
  assert_eq "$h" "$(shasum -a 256 "$t/CLAUDE.md" | awk '{print $1}')"
}
test_reinstall_same_version_is_noop() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  local before; before="$(cd "$t" && find . -type f -not -path './.git/*' -exec shasum -a 256 {} + | sort | shasum)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null) || fail "second run exited nonzero"
  local after; after="$(cd "$t" && find . -type f -not -path './.git/*' -exec shasum -a 256 {} + | sort | shasum)"
  assert_eq "$before" "$after"
}
test_existing_untracked_claude_md_is_skipped_with_warning() {
  local t; t="$(make_target_repo)"; echo mine > "$t/CLAUDE.md"
  local out; out="$(cd "$ROOT" && ./install.sh --tier 1 --target "$t" 2>&1)"
  assert_eq "mine" "$(cat "$t/CLAUDE.md")"
  echo "$out" | grep -q "SKIP" || fail "no skip warning"
}
test_force_adopts_existing_untracked_file() {
  local t; t="$(make_target_repo)"; echo mine > "$t/CLAUDE.md"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" --force >/dev/null)
  [ "$(cat "$t/CLAUDE.md")" != "mine" ] || fail "force did not overwrite"
  jq -e '.files[]|select(.path=="CLAUDE.md")' "$t/.build-system.json" >/dev/null || fail "not tracked"
}
test_dry_run_writes_nothing() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" --dry-run >/dev/null)
  assert_no_file "$t/CLAUDE.md"; assert_no_file "$t/.build-system.json"
}
test_non_git_target_fails_fast() {
  local d; d="$(mktemp -d)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$d" >/dev/null 2>&1) && fail "should have failed"
  assert_no_file "$d/CLAUDE.md"
}
```

- [ ] Step 2: Run → all new tests FAIL (`install.sh` absent).
- [ ] Step 3: Implement `install.sh` (~200 lines): arg parse; `require git repo`; `plan_files` walks `tiers/<n>-*/` for n ≤ requested tier (cumulative), emitting `src|dest` pairs (dest = path relative to the tier dir); dry-run prints `INSTALL/SKIP/OVERWRITE` plan; install loop honors skip/force; manifest written with `jq -n` from the installed-file list; same-version re-run compares hashes and exits 0 silently; higher-version manifest without `--upgrade` → error `run --upgrade`.
- [ ] Step 4: Run tests → all pass. `bash -n install.sh` clean.
- [ ] Step 5: Commit `feat(installer): tier-1 install with manifest, idempotency, dry-run, guards`.

### Task 4: Tier-2 pipeline artifacts (generalized)

**Files:**
- Create under `tiers/2-pipeline/`: `.github/ISSUE_TEMPLATE/change_request.yml`, `.github/workflows/{apply-risk-label,claude,claude-code-review}.yml`, `scripts/parse-risk-tier.cjs`, `.claude/commands/{build-next,triage-prs}.md`, and repo-root file `tiers/2-pipeline/labels.json`
- Test: append residue + presence tests

**Interfaces:**
- Produces: `labels.json` (installer consumes in Task 5): array of `{name,color,description}` for: `needs-triage` c5def5, `needs-info` fef2c0, `ready-for-agent` 0e8a16, `ready-for-human` d93f0b, `wontfix` ffffff, `plan:pending` fbca04, `plan:approved` 0e8a16, `plan:revise` d93f0b, `agent:building` 1d76db, `builder:paused` 000000, `triage:paused` 000000, `risk:docs` c2e0c6, `risk:chore` bfd4f2, `risk:feature` fbca04, `risk:risky` d93f0b.

Transformation rules (sources per spec Inputs table):
1. `change_request.yml` ($GSD): copy verbatim minus product-specific placeholder prose — replace the three placeholder examples mentioning app specifics ("Must not change the sync protocol…", "Not touching the MCP server…", "components/matrix, lib/sync…") with generic equivalents ("Must not change the public API. Must keep bundle size flat.", "Not refactoring adjacent modules.", "src/auth, lib/api, .github/workflows").
2. `apply-risk-label.yml` ($GSD): verbatim (already generic; keep the security header comment).
3. `parse-risk-tier.cjs` ($GSD): verbatim.
4. `claude.yml`, `claude-code-review.yml` ($BARO): verbatim.
5. `build-next.md` ($GSD `.claude/commands/build-next.md`): keep structure + priority order + Plan/Revise/Build/Escalate/Report sections verbatim EXCEPT: (a) "GSD Task Manager delivery pipeline" → "this repository's delivery pipeline"; (b) drop references to `docs/agents/*.md` and `docs/superpowers/plans/` → point to `docs/` of the build-system ("the pipeline docs installed with this system") and `coding-standards.md`; (c) hard-limits list: `.github/workflows/**` stays, "docker/** deploy config, CloudFront config" → "any path listed in `protectedPaths` in `.build-system.json`, deploy configuration"; (d) `claude/issue-<n>-*` → `<branchPrefix>/issue-<n>-*` with instruction "read `branchPrefix` from `.build-system.json` (default `claude`)"; (e) `bun run test/lint/typecheck` → "run every command in `verifyCommands` from `.build-system.json` and get them green"; (f) keep `OPENED_PR=` telemetry line verbatim.
6. `triage-prs.md` ($GSD): same treatment; `bun run …` reproduction list → `verifyCommands`; `bun install` lockfile fix → "regenerate the lockfile with the project's package manager"; branch pattern `claude/fix-*` → `<branchPrefix>/fix-*`; keep fork-provenance rules, ≤3 fix PRs, verify-before-submit, escalation, self-audit report verbatim in substance.

- [ ] Step 1: Write failing tests:

```bash
test_tier2_source_tree_complete() {
  for f in .github/ISSUE_TEMPLATE/change_request.yml .github/workflows/apply-risk-label.yml \
    .github/workflows/claude.yml .github/workflows/claude-code-review.yml \
    scripts/parse-risk-tier.cjs .claude/commands/build-next.md .claude/commands/triage-prs.md; do
    assert_file "$ROOT/tiers/2-pipeline/$f"
  done
  assert_file "$ROOT/tiers/2-pipeline/labels.json"
  assert_eq "15" "$(jq length "$ROOT/tiers/2-pipeline/labels.json")"
}
test_generalized_artifacts_have_no_gsd_residue() {
  local hits; hits="$(grep -riE 'gsd|cloudfront|taskmanager' "$ROOT/tiers/" || true)"
  assert_eq "" "$hits"
}
test_build_next_reads_manifest_config() {
  assert_grep "$ROOT/tiers/2-pipeline/.claude/commands/build-next.md" 'build-system\.json'
  assert_grep "$ROOT/tiers/2-pipeline/.claude/commands/build-next.md" 'OPENED_PR='
  assert_grep "$ROOT/tiers/2-pipeline/.claude/commands/build-next.md" 'never merge'
}
```

- [ ] Step 2: Run → FAIL. Create the files per the transformation rules. `labels.json` is not installed to the target tree (installer reads it in place), so keep it at `tiers/2-pipeline/labels.json` but EXCLUDE it in `plan_files` (add exclusion list `labels.json` at tier root).
- [ ] Step 3: Run tests → pass (residue test especially). Commit `feat(pipeline): add generalized tier-2 issue contract, workflows, and agent commands`.

### Task 5: Installer tier-2 support + labels via gh (mocked in tests)

**Files:**
- Modify: `install.sh` (labels step, tier-root exclusions)
- Test: append

**Interfaces:**
- Produces: after tier-2 copy, if `gh auth status` succeeds, run for each entry in `labels.json`: `gh label create <name> --color <color> --description <desc> --force`; else print the same commands prefixed `MANUAL:` and continue (exit 0).

- [ ] Step 1: Failing tests (PATH-shim mock):

```bash
make_gh_mock() {  # $1=dir  $2=mode(ok|absent)
  [ "$2" = absent ] && return 0
  cat > "$1/gh" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${GH_MOCK_LOG:?}"; exit 0
EOF
  chmod +x "$1/gh"
}
test_tier2_is_cumulative_and_adds_pipeline_artifacts() {
  local t; t="$(make_target_repo)"; local bin; bin="$(mktemp -d)"; make_gh_mock "$bin" ok
  ( export GH_MOCK_LOG="$bin/log" PATH="$bin:$PATH"
    cd "$ROOT" && ./install.sh --tier 2 --target "$t" >/dev/null )
  assert_file "$t/CLAUDE.md"   # cumulative: tier 1 included
  assert_file "$t/.github/ISSUE_TEMPLATE/change_request.yml"
  assert_file "$t/.claude/commands/build-next.md"
  assert_file "$t/scripts/parse-risk-tier.cjs"
  assert_no_file "$t/labels.json"
  assert_eq "2" "$(jq -r .tier "$t/.build-system.json")"
  grep -q "label create ready-for-agent" "$bin/log" || fail "labels not applied"
  assert_eq "15" "$(grep -c "label create" "$bin/log")"
}
test_missing_gh_labels_step_is_nonfatal() {
  local t; t="$(make_target_repo)"
  local out; out="$( PATH="/usr/bin:/bin" ROOT="$ROOT" sh -c 'cd "$ROOT" && ./install.sh --tier 2 --target '"$t"' 2>&1' )" || fail "nonzero exit"
  echo "$out" | grep -q "MANUAL:" || fail "no manual fallback printed"
}
```

(Adjust the second test if `jq`/`git` live outside `/usr/bin:/bin` on the runner — build a shim dir containing symlinks to everything except `gh` instead of truncating PATH.)
- [ ] Step 2: Run → FAIL. Implement labels step + `gh auth status` gate in `install.sh`.
- [ ] Step 3: Run → pass. Commit `feat(installer): tier-2 install applies label state machine via gh with manual fallback`.

### Task 6: Upgrade path

**Files:**
- Modify: `install.sh`
- Test: append

**Interfaces:**
- Produces: `./install.sh --upgrade [--target] [--dry-run] [--force]`. Per manifest-tracked file: current hash == recorded → re-copy from source tier + restamp hash; current != recorded (local edit) → leave, print `KEEP (locally modified): <path>`, `--force` overwrites; manifest `systemVersion` updated to repo `VERSION`. Corrupt manifest (jq parse fails) → exit 1 pointing at file, suggest `--force` reinstall via `--tier`.

- [ ] Step 1: Failing tests:

```bash
test_upgrade_resyncs_unmodified_and_preserves_modified() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "local tweak" >> "$t/CLAUDE.md"                      # local edit
  local fake="$ROOT/tiers/1-session/tasks/lessons.md"
  cp "$fake" "$fake.bak"; echo "upstream change" >> "$fake"  # upstream edit
  echo "2.0.1" > "$ROOT/VERSION.bak.orig"; cp "$ROOT/VERSION" "$ROOT/VERSION.bak"; echo "2.0.1" > "$ROOT/VERSION"
  local out; out="$(cd "$ROOT" && ./install.sh --upgrade --target "$t" 2>&1)"
  mv "$fake.bak" "$fake"; mv "$ROOT/VERSION.bak" "$ROOT/VERSION"; rm -f "$ROOT/VERSION.bak.orig"
  grep -q "local tweak" "$t/CLAUDE.md" || fail "clobbered local edit"
  echo "$out" | grep -q "KEEP" || fail "no KEEP notice"
  grep -q "upstream change" "$t/tasks/lessons.md" || fail "did not resync unmodified file"
  assert_eq "2.0.1" "$(jq -r .systemVersion "$t/.build-system.json")"
}
test_upgrade_force_overwrites_local_modification() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "local tweak" >> "$t/CLAUDE.md"
  (cd "$ROOT" && ./install.sh --upgrade --target "$t" --force >/dev/null)
  grep -q "local tweak" "$t/CLAUDE.md" && fail "force kept local edit"; true
}
test_corrupt_manifest_fails_fast() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "{not json" > "$t/.build-system.json"
  (cd "$ROOT" && ./install.sh --upgrade --target "$t" >/dev/null 2>&1) && fail "should fail"; true
}
```

- [ ] Step 2: Run → FAIL. Implement upgrade in `install.sh` (restore-safety note: tests mutate `$ROOT` files and restore them — keep that pattern; never leave the working tree dirty after a test run; verify with `git status --short` in the test's teardown).
- [ ] Step 3: Run full suite → pass, `git status` clean. Commit `feat(installer): three-way upgrade with local-modification preservation`.

### Task 7: Tier-3 ops — generalized drivers, night shift, scheduler artifacts

**Files:**
- Create under `tiers/3-ops/`: `local/{builder-run.sh,triage-run.sh,com.build-system.builder.plist.template,com.build-system.night-shift.plist.template}`, `local/failing-agent-prs.cjs`, `local/extract-run-tokens.cjs`, `night-shift-command/.claude/commands/night-shift.md`
- Modify: `install.sh` (tier 3: copy `local/*` → target `scripts/build-system/`, night-shift command → `.claude/commands/`; darwin prints launchctl instructions, else cron stanza; create `~/.build-system/<repo-name>.env` from a heredoc if absent)
- Test: append

**Interfaces:**
- Produces: env file contract consumed by both drivers:

```bash
# ~/.build-system/<repo>.env — machine-local settings for the ops drivers
BS_REPO="owner/name"            # gh repo slug (REQUIRED)
BS_SOURCE="$HOME/path/to/repo"  # local checkout (REQUIRED)
BS_WORKTREE="$HOME/.build-system/<repo>/worktree"
BS_LOG_DIR="$BS_SOURCE/docs/ops/agent-logs"
BS_CLAUDE_ARGS=""               # extra flags for claude -p
```

Transformation rules for `builder-run.sh`/`triage-run.sh` ($GSD sources): keep structure verbatim (PATH append, mode flags, fail-safe `count()`, kill switch, cheap work check, worktree isolation, scoped `--allowedTools`, run logging) EXCEPT: (a) `GSD_*` env vars → `BS_*` sourced from `"$HOME/.build-system/$(basename "$BS_SOURCE").env"` (require the env file, error if missing); (b) drop hardcoded defaults `vscarpenter/gsd-task-manager` etc.; (c) `Bash(bun*)` in allowedTools → read from optional `BS_ALLOWED_TOOLS` with default `"Bash(git*),Bash(gh*),Edit,Write,Read"`; (d) tokens-helper step becomes optional: only runs if `extract-run-tokens.cjs` exists next to the script; (e) helper `.cjs` files copied verbatim except `GSD_TRIAGE_REPO_OWNER` → `BS_TRIAGE_REPO_OWNER`; (f) `builder:paused` / `triage:paused` kill switches, `OPENED_PR` pairing, fork-provenance logic all survive verbatim.

`night-shift.md` command: the `triage-prs.md` generalization from Task 4 is the per-run instruction set; tier 3's `night-shift.md` is NOT a duplicate — it is the durable operating spec adapted from `$GSD/docs/agents/night-shift.md` (loop diagram, auto-fix/escalate/skip table with `verifyCommands` in place of bun commands, the two invariants verbatim, hard limits, kill switch) installed as `docs/night-shift.md` in the target (not a command). Correct the Files line: create `tiers/3-ops/docs/night-shift.md`.

launchd plist templates: standard `launchd.plist` XML with `{{LABEL}}`, `{{SCRIPT_PATH}}`, `{{HOUR}}` placeholders and a comment header telling the human to fill + `launchctl load`; installer prints instructions, never loads.

- [ ] Step 1: Failing tests:

```bash
test_tier3_adds_ops_scripts_and_scheduler_artifacts() {
  local t; t="$(make_target_repo)"; local bin; bin="$(mktemp -d)"; make_gh_mock "$bin" ok
  ( export GH_MOCK_LOG="$bin/log" PATH="$bin:$PATH" HOME="$(mktemp -d)"
    cd "$ROOT" && ./install.sh --tier 3 --target "$t" >/dev/null )
  assert_file "$t/scripts/build-system/builder-run.sh"
  assert_file "$t/scripts/build-system/triage-run.sh"
  assert_file "$t/scripts/build-system/failing-agent-prs.cjs"
  assert_file "$t/docs/night-shift.md"
  assert_eq "3" "$(jq -r .tier "$t/.build-system.json")"
}
test_ops_scripts_pass_bash_syntax_check() {
  bash -n "$ROOT/tiers/3-ops/local/builder-run.sh" || fail "builder-run syntax"
  bash -n "$ROOT/tiers/3-ops/local/triage-run.sh" || fail "triage-run syntax"
}
```

- [ ] Step 2: Run → FAIL. Create artifacts per rules; extend `plan_files` for tier 3's non-mirrored layout (map `local/*` → `scripts/build-system/`, `docs/night-shift.md` → `docs/`, plist templates → `scripts/build-system/`).
- [ ] Step 3: Run full suite (residue test now covers tier 3 too) → pass. Commit `feat(ops): generalized local drivers, night-shift spec, scheduler templates`.

### Task 8: Hosted builder variant (Actions)

**Files:**
- Create: `tiers/3-ops/actions/actions-builder.yml` (installed to `.github/workflows/actions-builder.yml`)
- Test: append presence + a `python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))"`-free check (no python dep: instead assert key strings)

- [ ] Step 1: Failing test:

```bash
test_actions_builder_variant_present_and_wired() {
  local f="$ROOT/tiers/3-ops/actions/actions-builder.yml"
  assert_file "$f"
  assert_grep "$f" 'anthropics/claude-code-action@v1'
  assert_grep "$f" 'plan:approved'
  assert_grep "$f" 'CLAUDE_CODE_OAUTH_TOKEN'
  assert_grep "$f" '/build-next'
}
```

- [ ] Step 2: Write the workflow:

```yaml
name: Hosted builder (reference variant)
# The local launchd/cron driver is the primary, battle-tested path; this is
# the hosted equivalent for repos without an always-on machine. Same contract:
# it runs /build-next, which never merges and obeys .build-system.json.
on:
  issues:
    types: [labeled]
  schedule:
    - cron: "0 13 * * 1-5"   # optional daily sweep; delete if label-only
  workflow_dispatch: {}
concurrency: { group: hosted-builder, cancel-in-progress: false }
permissions:
  contents: write        # push the claude/issue-* branch
  pull-requests: write   # open the PR
  issues: write          # move pipeline labels
  id-token: write
jobs:
  build-next:
    if: |
      github.event_name != 'issues' ||
      contains(fromJSON('["plan:approved","ready-for-agent","plan:revise"]'), github.event.label.name)
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: "/build-next"
          claude_args: '--allowed-tools "Bash(git*),Bash(gh*),Edit,Write,Read"'
```

- [ ] Step 3: Run tests → pass. Commit `feat(ops): hosted Actions builder variant`.

### Task 9: Docs — architecture, adoption, runbook, rationale, customizing

**Files:**
- Create: `docs/{architecture,adoption,runbook,customizing}.md`; Modify: `docs/RATIONALE.md` → `git mv` to `docs/rationale.md` + extend

Content requirements (each doc; write in vinny-voice; no marketing prose):
1. `architecture.md`: the generic pipeline narrative — contract issue → risk label → plan (Gate 1) → build → PR → reviewer+CI → Gate 2 → merge; night shift as maintenance loop; mermaid `stateDiagram-v2` of the label machine (states = the 15 labels' lifecycle subset: needs-triage → needs-info/ready-for-agent → plan:pending → plan:approved/plan:revise → agent:building → ready-for-human/done); the two invariants quoted; kill switches (`builder:paused`, `triage:paused`, `WORKFLOW_KILLSWITCH` note).
2. `adoption.md`: tier table (what you get / what you need / time to adopt); growth path 1→2→3; the manifest and how `--upgrade` works; standards versioning story.
3. `runbook.md`: operating gates (approving `plan:pending`, `/revise` comments), reading the builder's `OPENED_PR` telemetry, pausing, failure modes (gh auth expiry, worktree drift, claude CLI missing), cost notes.
4. `rationale.md`: keep v1 content; add v2 sections: installer-over-plugin, manifest hashes over git subtree, JSON-no-comments placeholder convention, local-first-over-hosted, deliberate cuts list from spec Out of Scope.
5. `customizing.md`: editing `.build-system.json` config keys with examples per stack (bun/npm, cargo, swift, maven); adapting hard limits; swapping `branchPrefix`; label renames (edit labels.json + commands consistently).

- [ ] Step 1: Write all five docs. Step 2: Add consistency test:

```bash
test_docs_reference_real_flags_and_paths() {
  for d in architecture adoption runbook rationale customizing; do assert_file "$ROOT/docs/$d.md"; done
  assert_grep "$ROOT/docs/adoption.md" '\-\-upgrade'
  assert_grep "$ROOT/docs/architecture.md" 'stateDiagram'
  # every install path a doc mentions must exist in tiers/
  grep -q 'tiers/1-session' "$ROOT/docs/adoption.md" || fail "adoption missing tier paths"
}
```

- [ ] Step 3: Tests pass. Commit `docs(v2): architecture, adoption, runbook, rationale, customizing`.

### Task 10: README rewrite + v1→v2 map + CHANGELOG

**Files:**
- Modify: `README.md` (full rewrite), `CHANGELOG.md`

Requirements: front-door what/why paragraph (evolves the published v1 framing, links both posts); tier quickstarts as copy-paste `./install.sh` blocks; the six-principles table updated to v2 paths; **v1 → v2 map table** (`templates/CLAUDE.md → tiers/1-session/CLAUDE.md`, `examples/coding-standards.md → standards/coding-standards.md`, `.claude/* → tiers/1-session/.claude/*`, `global/ → unchanged`); disclaimer + contributing + license sections survive; "Last updated / Tested on" refreshed.

- [ ] Step 1: Rewrite README. Step 2: `test_readme_quickstart_commands_are_real`: assert README contains `./install.sh --tier 1` and the v1→v2 map table header. Step 3: Suite green. Commit `docs(readme): v2 front door with tier quickstarts and v1 map`.

### Task 11: Pilot — tier-2 install into kanban-todos (local only)

- [ ] Step 1: `git -C ~/Projects/kanban-todos status --short` — require clean tree; if dirty, stash nothing, just report and do the pilot in a fresh clone under the scratchpad instead.
- [ ] Step 2: Run `./install.sh --tier 2 --target ~/Projects/kanban-todos --dry-run`, then real run. Expected: SKIP warnings for pre-existing `CLAUDE.md`, `.claude/settings.json`(if present), `claude.yml`, `claude-code-review.yml`; new files installed; manifest written; labels step runs (gh authed) or prints MANUAL.
- [ ] Step 3: Verify per spec AC11 checklist; record results in `tasks/implementation-notes.md`. **Do not commit/push anything in kanban-todos without explicit user confirmation** — leave the working tree for the user to review, and say so in the final report.

### Task 12: Blog draft

- [ ] Step 1: Invoke the vinny-voice skill. Write `~/Projects/VinnyThesis/2026-08-07-the-pipeline-becomes-a-package.md`: arc = hand-fitted pipeline (Two Gates) → extracted installable system; cover tiers, manifest/upgrade, standards drift fix, local-first + hosted variant, what's deliberately missing; link `2026-04-25-claude-code-build-system` and `2026-07-06-two-gates-and-a-night-shift`. Match front-matter format of existing VinnyThesis posts (check one first).
- [ ] Step 2: Self-review against vinny-voice rules. Not committed to this repo (VinnyThesis is its own dir; leave file untracked for Vinny).

### Task 13: Finish line

- [ ] Step 1: Full suite green; `git status` clean in build-system repo; residue grep clean; `bash -n` on all shipped shell.
- [ ] Step 2: Update `tasks/todo.md` with "Resuming From Here"; distill `tasks/implementation-notes.md` → `tasks/lessons.md`; delete the ledger.
- [ ] Step 3: Final commit `chore(release): 2.0.0 changelog and handoff notes`. NO push without user go-ahead.
- [ ] Step 4: Deliver change report + comprehension quiz (non-trivial tier), sized ~5 questions.
