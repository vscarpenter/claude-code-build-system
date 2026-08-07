#!/usr/bin/env bash
# Test harness for the installer. Plain bash on purpose: the installer's whole
# pitch is zero runtime dependencies, so its tests get the same constraint.
# The exception is the night-shift helper, which is a node module and so needs
# node to exercise; the driver that calls it already hard-depends on node.
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

RISK_PARSER="$ROOT/tiers/2-pipeline/scripts/parse-risk-tier.cjs"
RISK_FORM="$ROOT/tiers/2-pipeline/.github/ISSUE_TEMPLATE/change_request.yml"

risk_tier() {  # $1 = rendered issue body; echoes the parsed tier, or "null"
  node -e '
    const { parseRiskTier } = require(process.argv[1]);
    process.stdout.write(String(parseRiskTier(process.argv[2])));
  ' "$RISK_PARSER" "$1"
}

risk_body() { printf '### Risk tier\n\n%s\n' "$1"; }

test_risk_tier_parses_every_dropdown_option() {
  local tier
  for tier in docs chore feature risky; do
    assert_eq "$tier" "$(risk_tier "$(risk_body "$tier")")" "for $tier"
  done
}

test_risk_tier_is_case_insensitive_in_heading_and_value() {
  assert_eq "feature" "$(risk_tier "$(printf '### RISK TIER\n\nFeature\n')")"
  # Also covers whitespace padding around the answer.
  assert_eq "risky" "$(risk_tier "$(printf '### Risk Tier\n\n  RISKY  \n')")"
}

test_risk_tier_accepts_every_markdown_heading_level() {
  local h
  for h in '#' '##' '###' '####' '#####' '######'; do
    assert_eq "feature" "$(risk_tier "$(printf '%s Risk tier\n\nfeature\n' "$h")")" "for heading '$h'"
  done
  # Seven hashes is not a heading in Markdown and must not match.
  assert_eq "null" "$(risk_tier "$(printf '####### Risk tier\n\nfeature\n')")"
}

test_risk_tier_heading_must_match_the_label_exactly() {
  # "### Risk tier rationale" is a different section. Matching it would read the
  # answer out of the wrong field, and would win because the first match is used.
  assert_eq "null" "$(risk_tier "$(printf '### Risk tier rationale\n\nfeature\n')")"
  assert_eq "docs" "$(risk_tier "$(printf '### Risk tier rationale\n\nfeature\n\n### Risk tier\n\ndocs\n')")"
}

test_risk_tier_handles_crlf_bodies() {
  # GitHub delivers issue bodies with CRLF line endings.
  assert_eq "chore" "$(risk_tier "$(printf '### Risk tier\r\n\r\nchore\r\n')")"
}

test_risk_tier_rejects_unanswered_junk_and_missing_sections() {
  assert_eq "null" "$(risk_tier "$(risk_body '_No response_')")" "unanswered dropdown"
  assert_eq "null" "$(risk_tier "$(risk_body 'medium')")" "value outside RISK_TIERS"
  assert_eq "null" "$(risk_tier "$(risk_body 'risky is my guess')")" "prose around a valid word"
  assert_eq "null" "$(risk_tier "$(printf '### Summary\n\nno risk section here\n')")" "heading absent"
  assert_eq "null" "$(risk_tier "$(printf '### Risk tier\n\n### Affected areas\n\nsrc/\n')")" "empty section"
  assert_eq "null" "$(risk_tier "$(printf '### Risk tier\n')")" "heading then end of body"
}

test_risk_tier_rejects_non_string_input() {
  # The workflow hands it context.payload.issue.body, which is null on issues
  # opened with no body at all.
  local out; out="$(node -e '
    const { parseRiskTier } = require(process.argv[1]);
    process.stdout.write([undefined, null, 42, {}, [], ""].map((c) => String(parseRiskTier(c))).join(","));
  ' "$RISK_PARSER")"
  assert_eq "null,null,null,null,null,null" "$out"
}

test_risk_tier_parses_a_realistic_rendered_form_body() {
  # GitHub renders one "### <label>" section per field, in form order; the
  # dropdown is the sixth of eight.
  local body; body="$(printf '%s\n' \
    '### Summary' '' 'The footer shows a stale year.' '' \
    '### Acceptance criteria' '' '- [ ] Footer shows the current year' '' \
    '### Constraints' '' 'None' '' \
    '### Out of scope' '' 'Nothing else' '' \
    '### Rollback considerations' '' 'Revert the PR' '' \
    '### Risk tier' '' 'chore' '' \
    '### Affected areas (optional)' '' '_No response_')"
  assert_eq "chore" "$(risk_tier "$body")"
}

test_risk_tiers_match_the_issue_form_dropdown() {
  # Two lists that must stay identical: a rename in one place leaves the
  # labeler silently unable to match any answer.
  local form; form="$(sed -n '/id: risk$/,/validations/p' "$RISK_FORM" \
    | sed -n 's/^ *- \([a-z]*\)$/\1/p' | tr '\n' ',')"
  local mod; mod="$(node -e '
    process.stdout.write(require(process.argv[1]).RISK_TIERS.join(",") + ",");
  ' "$RISK_PARSER")"
  assert_eq "$form" "$mod"
  assert_eq "docs,chore,feature,risky," "$mod"   # guards against both going empty
}

test_risk_workflow_requires_the_installed_parser_path() {
  # The workflow requires the parser by path from GITHUB_WORKSPACE; the
  # installer places it at scripts/. Same wiring class as the night shift's.
  assert_grep "$ROOT/tiers/2-pipeline/.github/workflows/apply-risk-label.yml" \
    'scripts/parse-risk-tier\.cjs'
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

# Three same-repo PRs with failing checks, differing only in branch prefix: the
# fleet's default, a renamed fleet, and a hand-written human branch.
NIGHT_SHIFT_PRS='[
  {"number":1,"headRefName":"claude/issue-1-a","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]},
  {"number":2,"headRefName":"bot/issue-2-b","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]},
  {"number":3,"headRefName":"feature/hand-written","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]}
]'

# Same idea for the driver test, but with two renamed-fleet PRs so the expected
# count (2) differs from what the old hardcoded-claude/ helper would report (1).
# A fixture where both answers are 1 would pass with the bug still in place.
NIGHT_SHIFT_RENAMED_PRS='[
  {"number":1,"headRefName":"claude/issue-1-a","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]},
  {"number":2,"headRefName":"bot/issue-2-b","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]},
  {"number":3,"headRefName":"bot/issue-3-c","isCrossRepository":false,"statusCheckRollup":[{"conclusion":"failure"}]}
]'

agent_pr_numbers() {  # $1 = branch prefix ("-" omits the argument), $2 = PR JSON
  node -e '
    const { failingAgentPRs } = require(process.argv[1]);
    const prefix = process.argv[2] === "-" ? undefined : process.argv[2];
    process.stdout.write(
      failingAgentPRs(JSON.parse(process.argv[3]), "acme", prefix).map((p) => p.number).join(",")
    );
  ' "$ROOT/tiers/3-ops/local/failing-agent-prs.cjs" "$1" "$2"
}

test_night_shift_helper_defaults_to_the_claude_prefix() {
  assert_eq "1" "$(agent_pr_numbers - "$NIGHT_SHIFT_PRS")"
}

test_night_shift_helper_honors_a_custom_branch_prefix() {
  assert_eq "2" "$(agent_pr_numbers bot "$NIGHT_SHIFT_PRS")"
}

test_branch_prefix_tolerates_a_hand_written_trailing_slash() {
  # config.branchPrefix is hand-edited JSON; "bot/" is a plausible entry and
  # must not become "bot//".
  assert_eq "2" "$(agent_pr_numbers "bot/" "$NIGHT_SHIFT_PRS")"
}

test_blank_branch_prefix_does_not_match_every_pr() {
  # A "" prefix must never reach startsWith(""), which is true for every branch
  # name and would hand the night shift every failing PR in the repo — including
  # hand-written human ones. Fail safe to the default instead.
  assert_eq "1" "$(agent_pr_numbers "" "$NIGHT_SHIFT_PRS")"
}

make_gh_pr_mock() {  # $1 = bin dir, $2 = PR list JSON; issue list answers the kill switch
  cat > "$1/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"issue list"*) echo 0 ;;
  *"pr list"*) cat <<'JSON'
$2
JSON
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$1/gh" 2>/dev/null || /bin/chmod +x "$1/gh"
}

# The regression that motivated threading the prefix: the helper hardcoded
# claude/, so a repo that renamed branchPrefix got a night shift that reported
# no work forever. Exercises the whole wiring — manifest to driver to helper.
test_triage_driver_passes_manifest_branch_prefix_to_the_helper() {
  local t; t="$(make_target_repo)"
  local bin; bin="$(mktemp -d)"; local home; home="$(mktemp -d)"
  ( export GH_MOCK_LOG="$bin/log" PATH="$bin:$PATH" HOME="$home"
    make_gh_mock "$bin"
    cd "$ROOT" && ./install.sh --tier 3 --target "$t" >/dev/null ) || fail "install exited nonzero"

  jq '.config.branchPrefix = "bot"' "$t/.build-system.json" > "$t/.m" && mv "$t/.m" "$t/.build-system.json"
  mkdir -p "$home/.build-system"
  printf 'BS_REPO="acme/widget"\n' > "$home/.build-system/$(basename "$t").env"
  make_gh_pr_mock "$bin" "$NIGHT_SHIFT_RENAMED_PRS"

  local out
  out="$( export PATH="$bin:$PATH" HOME="$home"
    bash "$t/scripts/build-system/triage-run.sh" --check 2>&1 )"
  echo "$out" | grep -q "WORK: failing agent PRs=2" \
    || fail "driver did not use the manifest prefix (got: $out)"
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
