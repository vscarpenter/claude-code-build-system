#!/bin/bash
# ~/.claude/hooks/persist-memory.sh
#
# Fires on SessionEnd. Reads the session transcript at transcript_path,
# pipes it into a fresh `claude --print` invocation, asks the model to
# extract one to three reusable learnings, and appends them to the
# global lessons file. Claude summarizes Claude.
#
# Register in ~/.claude/settings.json under hooks.SessionEnd.
#
# Cost note: each session-end fires a nested API call. Budget for it.

set -u

MEMORY_FILE="${CLAUDE_MEMORY_FILE:-$HOME/.claude/lessons.md}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

# Read the hook input from stdin
INPUT=$(cat)

# Extract the transcript path from the hook payload
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Bail quietly if there's nothing to read
[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ ! -r "$TRANSCRIPT_PATH" ] && exit 0

# Pipe the transcript JSONL into claude --print and extract learnings
LEARNINGS=$(cat "$TRANSCRIPT_PATH" | claude --print \
  "Review this Claude Code session transcript. Extract 1-3 specific, reusable
   learnings or decisions. Format each as a single bullet:
   '- [YYYY-MM-DD] <concise learning>'. Only include genuine insights
   worth persisting. Output nothing if there are none.")

# Append to the lessons file if anything came back
if [ -n "$LEARNINGS" ]; then
  {
    echo ""
    echo "<!-- Session: $TIMESTAMP -->"
    echo "$LEARNINGS"
  } >> "$MEMORY_FILE"
fi

exit 0
