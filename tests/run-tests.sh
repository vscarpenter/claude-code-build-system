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
  for f in CLAUDE.md coding-standards.md .claude/settings.json \
    .claude/commands/qspec.md .claude/commands/tdd.md .claude/commands/qcheck.md \
    .claude/hooks/format-edits.sh .claude/hooks/protect-files.sh \
    tasks/lessons.md tasks/todo.md; do
    assert_file "$ROOT/tiers/1-session/$f"
  done
}

main() {
  for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
  echo "passed=$PASS failed=$FAIL"
  [ $FAIL -eq 0 ]
}
main
