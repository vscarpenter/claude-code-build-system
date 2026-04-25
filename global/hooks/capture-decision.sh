#!/bin/bash
# ~/.claude/hooks/capture-decision.sh
#
# Fires on PostToolUse for Edit and Write. Captures the file path, session ID,
# and a git diff --stat snapshot to a daily decision log. When a regression
# shows up two weeks later, scroll back through the log to find the cause.
#
# Register in ~/.claude/settings.json under hooks.PostToolUse with matcher
# "Edit|Write|MultiEdit".

set -u

DECISION_DIR="${CLAUDE_DECISION_DIR:-$HOME/.claude/decisions}"
mkdir -p "$DECISION_DIR"

DATE=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$DECISION_DIR/decisions-$DATE.log"

# Read the hook input from stdin
INPUT=$(cat)

# Extract session_id, tool_name, and file_path
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# Get a git diff --stat snapshot if we're in a git repo
DIFF_STAT=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ]; then
  DIFF_STAT=$(cd "$CWD" && git diff --stat HEAD 2>/dev/null | tail -1 || echo "")
fi

# Log the mutation
{
  echo "[$TIMESTAMP] [$SESSION_ID]"
  echo "  tool: $TOOL_NAME"
  echo "  file: $FILE_PATH"
  if [ -n "$DIFF_STAT" ]; then
    echo "  diff: $DIFF_STAT"
  fi
  echo ""
} >> "$LOG_FILE"

exit 0
