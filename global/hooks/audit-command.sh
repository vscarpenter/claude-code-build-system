#!/bin/bash
# ~/.claude/hooks/audit-command.sh
#
# Fires on PreToolUse for Bash. Logs every command with timestamp and session ID.
# Pattern-matches against high-risk command shapes and routes flagged commands
# to a separate log. This is an audit trail, not a blocker. Always exits 0.
#
# Register in ~/.claude/settings.json under hooks.PreToolUse with matcher "Bash".

set -u

AUDIT_DIR="${CLAUDE_AUDIT_DIR:-$HOME/.claude/audit}"
mkdir -p "$AUDIT_DIR"

DATE=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="$AUDIT_DIR/audit-$DATE.log"
FLAGGED_FILE="$AUDIT_DIR/flagged-$DATE.log"

# Read the hook input from stdin
INPUT=$(cat)

# Extract session_id and command using jq
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Always log to the audit file
echo "[$TIMESTAMP] [$SESSION_ID] $COMMAND" >> "$LOG_FILE"

# Pattern match against high-risk shapes
# Add or remove patterns to match your risk tolerance
RISKY_PATTERNS=(
  'curl[^|]*\| *sh'
  'curl[^|]*\| *bash'
  'wget[^|]*\| *sh'
  'wget[^|]*\| *bash'
  'eval '
  'exec '
  'git push --force'
  'git push -f'
  'rm -rf /'
  'sudo rm'
  'chmod 777'
  '> *~/\.ssh'
  '> *~/\.aws'
)

for pattern in "${RISKY_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "[$TIMESTAMP] [$SESSION_ID] [pattern: $pattern] $COMMAND" >> "$FLAGGED_FILE"
    break
  fi
done

# Exit 0 always: this is an audit trail, not a blocker
exit 0
