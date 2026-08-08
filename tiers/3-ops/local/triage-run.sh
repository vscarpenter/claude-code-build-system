#!/usr/bin/env bash
# Provenance-bound night-shift entry point. This is intentionally diagnosis
# only: no model receives Git/GitHub credentials or is allowed to patch a PR.
set -euo pipefail
umask 077

RUNTIME_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONTROLLER="$RUNTIME_DIR/build-system.cjs"
[ -f "$CONTROLLER" ] || CONTROLLER="$RUNTIME_DIR/../build-system.cjs"
CONFIG_FILE="${BS_RUNTIME_CONFIG:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || { echo "ERROR: --config requires a value" >&2; exit 2; }; CONFIG_FILE="$2"; shift 2 ;;
    --check|--dry-run) shift ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$CONTROLLER" ] || { echo "ERROR: immutable controller missing: $CONTROLLER" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "ERROR: node is required" >&2; exit 1; }

RUNTIME_MANIFEST="$RUNTIME_DIR/runtime-manifest.json"
if [ -f "$RUNTIME_MANIFEST" ]; then
  while IFS=$'\t' read -r rel expected; do
    [ -f "$RUNTIME_DIR/$rel" ] || { echo "ERROR: immutable runtime file missing: $rel" >&2; exit 1; }
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$RUNTIME_DIR/$rel" | awk '{print $1}')"
    else
      actual="$(sha256sum "$RUNTIME_DIR/$rel" | awk '{print $1}')"
    fi
    [ "$actual" = "$expected" ] || { echo "ERROR: immutable runtime integrity check failed: $rel" >&2; exit 1; }
  done < <(jq -r '.files[] | [.path,.sha256] | @tsv' "$RUNTIME_MANIFEST")
fi

if [ -n "$CONFIG_FILE" ]; then
  [ -f "$CONFIG_FILE" ] || { echo "ERROR: runtime config not found: $CONFIG_FILE" >&2; exit 1; }
  SOURCE="$(jq -er '.source | select(type=="string" and length>0)' "$CONFIG_FILE")" \
    || { echo "ERROR: runtime config requires source" >&2; exit 1; }
else
  SOURCE="$(cd "$RUNTIME_DIR/../.." && pwd -P)"
fi

[ -d "$SOURCE" ] || { echo "ERROR: source repository not found: $SOURCE" >&2; exit 1; }
cd "$SOURCE"
exec node "$CONTROLLER" triage --json
