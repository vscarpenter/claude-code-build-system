#!/bin/bash
# .claude/hooks/format-edits.sh
#
# Fires on PostToolUse for Edit, Write, and MultiEdit. Auto-formats edited
# TypeScript and JavaScript files with the project's linter.
#
# Replace `bunx eslint --fix` with your formatter of choice (prettier, biome,
# rustfmt, gofmt, swift-format, etc.) based on file extension.
#
# Register in .claude/settings.json under hooks.PostToolUse with matcher
# "Edit|Write|MultiEdit".

set -u

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

# Match by extension, dispatch to the right formatter
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    bunx eslint --fix "$FILE_PATH" 2>&1 | tail -5 || true
    ;;
  *.py)
    ruff format "$FILE_PATH" 2>&1 | tail -5 || true
    ;;
  *.rs)
    rustfmt "$FILE_PATH" 2>&1 | tail -5 || true
    ;;
  *.go)
    gofmt -w "$FILE_PATH" 2>&1 | tail -5 || true
    ;;
  *.swift)
    swift-format -i "$FILE_PATH" 2>&1 | tail -5 || true
    ;;
esac

# Always exit 0: formatting is best-effort, not a blocker
exit 0
