#!/usr/bin/env bash
# Test harness for the installer. Plain bash on purpose: the installer's whole
# pitch is zero runtime dependencies, so its tests get the same constraint.
# Each test_* function runs in isolation against a fresh temp git repo fixture.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; CURRENT=""

fail() { echo "FAIL[$CURRENT]: $*"; FAIL=$((FAIL+1)); }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$1' got '$2' ${3:-}"; }
assert_file() { [ -f "$1" ] || fail "missing file $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected file $1"; }
assert_grep() { grep -qE "$2" "$1" || fail "pattern '$2' not in $1"; }

make_target_repo() {  # echoes path to a fresh git repo with one commit
  local d; d="$(mktemp -d)"; git -C "$d" init -q
  git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  echo "$d"
}

run_test() {
  CURRENT="$1"; local before=$FAIL
  "$1"
  [ $FAIL -eq $before ] && { PASS=$((PASS+1)); echo "ok $1"; }
}

test_harness_self_check() { assert_eq "a" "a"; }

test_tier1_source_tree_complete() {
  for f in CLAUDE.md .claude/settings.json \
    .claude/commands/qspec.md .claude/commands/tdd.md .claude/commands/qcheck.md \
    .claude/hooks/format-edits.sh .claude/hooks/protect-files.sh \
    tasks/lessons.md tasks/todo.md; do
    assert_file "$ROOT/tiers/1-session/$f"
  done
}

# coding-standards.md is the one file tier 1 ships from outside its own tree.
# It used to be duplicated into tiers/1-session/, where the copy could drift
# from the canonical doc with nothing to catch it. These two tests pin the
# single-source arrangement that replaced it.
test_standards_have_exactly_one_copy_in_the_repo() {
  assert_file "$ROOT/standards/coding-standards.md"
  assert_eq "" "$(find "$ROOT/tiers" -name coding-standards.md)"
}

test_tier1_ships_the_canonical_standards_verbatim() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null) || fail "install exited nonzero"
  diff -q "$ROOT/standards/coding-standards.md" "$t/coding-standards.md" >/dev/null \
    || fail "installed coding-standards.md differs from standards/coding-standards.md"
}

test_tier1_fresh_install_places_files_and_manifest() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null) || fail "install exited nonzero"
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
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" --dry-run >/dev/null) || fail "dry-run exited nonzero"
  assert_no_file "$t/CLAUDE.md"; assert_no_file "$t/.build-system.json"
}

test_non_git_target_fails_fast() {
  local d; d="$(mktemp -d)"
  if (cd "$ROOT" && ./install.sh --tier 1 --target "$d" >/dev/null 2>&1); then fail "should have failed"; fi
  assert_no_file "$d/CLAUDE.md"
}

test_tier2_source_tree_complete() {
  for f in .github/ISSUE_TEMPLATE/change_request.yml .github/workflows/apply-risk-label.yml \
    .github/workflows/claude.yml .github/workflows/claude-code-review.yml \
    scripts/parse-risk-tier.cjs .claude/commands/build-next.md .claude/commands/triage-prs.md; do
    assert_file "$ROOT/tiers/2-pipeline/$f"
  done
  assert_file "$ROOT/tiers/2-pipeline/labels.json"
  assert_eq "15" "$(jq length "$ROOT/tiers/2-pipeline/labels.json" 2>/dev/null)"
}

test_generalized_artifacts_have_no_gsd_residue() {
  local hits; hits="$(grep -riE 'gsd|cloudfront|taskmanager' "$ROOT/tiers/" || true)"
  assert_eq "" "$hits"
}

test_build_next_reads_manifest_config() {
  local f="$ROOT/tiers/2-pipeline/.claude/commands/build-next.md"
  assert_grep "$f" 'build-system\.json'
  assert_grep "$f" 'OPENED_PR='
  assert_grep "$f" 'never merge'
}

make_gh_mock() {  # $1 = bin dir; creates a gh that logs args and succeeds
  cat > "$1/gh" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${GH_MOCK_LOG:?}"
exit 0
EOF
  chmod +x "$1/gh" 2>/dev/null || /bin/chmod +x "$1/gh"
}

test_tier2_is_cumulative_and_adds_pipeline_artifacts() {
  local t; t="$(make_target_repo)"; local bin; bin="$(mktemp -d)"; make_gh_mock "$bin"
  ( export GH_MOCK_LOG="$bin/log" PATH="$bin:$PATH"
    cd "$ROOT" && ./install.sh --tier 2 --target "$t" >/dev/null ) || fail "install exited nonzero"
  assert_file "$t/CLAUDE.md"
  assert_file "$t/coding-standards.md"   # tier 1's out-of-tree file still ships
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
  # A bin dir shadowing gh with a hard failure simulates gh missing/unauthed.
  local bin; bin="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$bin/gh"
  chmod +x "$bin/gh" 2>/dev/null || /bin/chmod +x "$bin/gh"
  local out
  out="$( export PATH="$bin:$PATH"
    cd "$ROOT" && ./install.sh --tier 2 --target "$t" 2>&1 )" || fail "nonzero exit"
  echo "$out" | grep -q "MANUAL:" || fail "no manual fallback printed"
}

# Upgrade tests mutate $ROOT (VERSION bump, one upstream file edit) and MUST
# restore it before returning, even on assertion failure.
test_upgrade_resyncs_unmodified_and_preserves_modified() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "local tweak" >> "$t/CLAUDE.md"                       # local edit → KEEP
  local up="$ROOT/tiers/1-session/tasks/lessons.md"
  cp "$up" "$up.bak"; echo "upstream change" >> "$up"        # upstream edit → resync
  cp "$ROOT/VERSION" "$ROOT/VERSION.bak"; echo "2.0.1" > "$ROOT/VERSION"
  local out; out="$(cd "$ROOT" && ./install.sh --upgrade --target "$t" 2>&1)" || fail "upgrade exited nonzero"
  mv "$up.bak" "$up"; mv "$ROOT/VERSION.bak" "$ROOT/VERSION" # restore repo
  grep -q "local tweak" "$t/CLAUDE.md" || fail "clobbered local edit"
  echo "$out" | grep -q "KEEP" || fail "no KEEP notice"
  grep -q "upstream change" "$t/tasks/lessons.md" || fail "did not resync unmodified file"
  assert_eq "2.0.1" "$(jq -r .systemVersion "$t/.build-system.json")"
}

test_upgrade_force_overwrites_local_modification() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "local tweak" >> "$t/CLAUDE.md"
  (cd "$ROOT" && ./install.sh --upgrade --target "$t" --force >/dev/null) || fail "upgrade exited nonzero"
  if grep -q "local tweak" "$t/CLAUDE.md"; then fail "force kept local edit"; fi
}

test_corrupt_manifest_fails_fast() {
  local t; t="$(make_target_repo)"
  (cd "$ROOT" && ./install.sh --tier 1 --target "$t" >/dev/null)
  echo "{not json" > "$t/.build-system.json"
  if (cd "$ROOT" && ./install.sh --upgrade --target "$t" >/dev/null 2>&1); then fail "should fail on corrupt manifest"; fi
}

test_tier3_adds_ops_scripts_and_scheduler_artifacts() {
  local t; t="$(make_target_repo)"; local bin; bin="$(mktemp -d)"; make_gh_mock "$bin"
  ( export GH_MOCK_LOG="$bin/log" PATH="$bin:$PATH" HOME="$(mktemp -d)"
    cd "$ROOT" && ./install.sh --tier 3 --target "$t" >/dev/null ) || fail "install exited nonzero"
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

test_actions_builder_variant_present_and_wired() {
  local f="$ROOT/tiers/3-ops/actions/actions-builder.yml"
  assert_file "$f"
  assert_grep "$f" 'anthropics/claude-code-action@v1'
  assert_grep "$f" 'plan:approved'
  assert_grep "$f" 'CLAUDE_CODE_OAUTH_TOKEN'
  assert_grep "$f" '/build-next'
}

test_docs_reference_real_flags_and_paths() {
  for d in architecture adoption runbook rationale customizing; do assert_file "$ROOT/docs/$d.md"; done
  assert_grep "$ROOT/docs/adoption.md" '\-\-upgrade'
  assert_grep "$ROOT/docs/architecture.md" 'stateDiagram'
  assert_grep "$ROOT/docs/adoption.md" 'tier 1'
}

test_readme_quickstart_commands_are_real() {
  assert_grep "$ROOT/README.md" 'install\.sh --tier 1'
  assert_grep "$ROOT/README.md" 'v1 → v2 map'
  assert_grep "$ROOT/README.md" '\-\-upgrade'
}

main() {
  for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
  echo "passed=$PASS failed=$FAIL"
  [ $FAIL -eq 0 ]
}
main
