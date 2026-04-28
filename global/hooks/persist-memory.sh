#!/bin/bash
# ~/.claude/hooks/persist-memory.sh
#
# Stop/SessionEnd hook: extract durable learnings from the session
# transcript and append them to a memory file.
#
# Manual test:
#   echo '{"transcript_path":"/path/to/transcript.jsonl"}' | ./persist-memory.sh

set -euo pipefail

MEMORY_FILE="${CLAUDE_MEMORY_FILE:-$HOME/.claude/lessons.md}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
DEBUG_LOG="${CLAUDE_HOOK_DEBUG_LOG:-$HOME/.claude/hooks/persist-memory.log}"

log() {
  [ -n "${CLAUDE_HOOK_DEBUG:-}" ] || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$DEBUG_LOG"
}

# Recursion guard: the `claude --print` call below spawns a nested session.
# If that session's SessionEnd fires hooks, this script would re-invoke
# itself and burn another API call on a transcript of its own prompt.
# An exported sentinel breaks the cycle — child processes inherit it.
if [ -n "${CLAUDE_PERSIST_MEMORY_RUNNING:-}" ]; then
  log "nested invocation detected; exiting 0"
  exit 0
fi
export CLAUDE_PERSIST_MEMORY_RUNNING=1

# Guard: refuse to block on a TTY if someone runs this directly.
if [ -t 0 ]; then
  echo "persist-memory.sh: expects hook JSON on stdin; refusing to read from TTY." >&2
  exit 1
fi

INPUT=$(cat)
log "hook invoked, input bytes=${#INPUT}"

# Activity gate: skip the API call if the session didn't mutate any files.
# capture-decision.sh logs every Edit/Write keyed by [session_id]; if there
# are no entries for this session, there's nothing meaningful to summarize.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
DECISION_DIR="${CLAUDE_DECISION_DIR:-$HOME/.claude/decisions}"
if [ -n "$SESSION_ID" ] && [ -d "$DECISION_DIR" ]; then
  TODAY=$(date '+%Y-%m-%d')
  # Long sessions can cross midnight, so check yesterday's log too.
  # `date -v-1d` is BSD/macOS; `date -d 'yesterday'` is GNU/Linux.
  YESTERDAY=$(date -v-1d '+%Y-%m-%d' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || echo "")
  TODAY_LOG="$DECISION_DIR/decisions-$TODAY.log"
  YESTERDAY_LOG="$DECISION_DIR/decisions-$YESTERDAY.log"
  if ! grep -q "\[$SESSION_ID\]" "$TODAY_LOG" 2>/dev/null \
     && ! grep -q "\[$SESSION_ID\]" "$YESTERDAY_LOG" 2>/dev/null; then
    log "no edits recorded for session $SESSION_ID; exiting 0"
    exit 0
  fi
fi

# Claude Code hook payloads expose the transcript as a file path.
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
log "transcript_path=${TRANSCRIPT_PATH:-<empty>}"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "no transcript file; exiting 0"
  exit 0
fi

# Cap the transcript we send to Claude. JSONL lines can be tens of KB each
# (tool results inline), so cap by BYTES not lines. ~64 KB is plenty of
# recent context and stays well under prompt limits.
MAX_BYTES=${CLAUDE_HOOK_TRANSCRIPT_BYTES:-65536}
TRANSCRIPT_TAIL=$(tail -c "$MAX_BYTES" "$TRANSCRIPT_PATH")
log "transcript_tail bytes=${#TRANSCRIPT_TAIL} (cap=$MAX_BYTES)"

if [ -z "$TRANSCRIPT_TAIL" ]; then
  log "empty tail; exiting 0"
  exit 0
fi

# Bound the call to Claude so a stuck CLI invocation can't hang the hook.
# Capture stderr + exit code so debug mode can show what went wrong.
STDERR_FILE=$(mktemp)
set +e
LEARNINGS=$(printf '%s' "$TRANSCRIPT_TAIL" | timeout 120 claude --print \
  "Review this session transcript (JSONL). Extract 1-3 specific, reusable learnings or decisions.
   Format each as a single bullet on its own line: '- [YYYY-MM-DD] <concise learning>'.
   Output ONLY the bullets — no preamble, no markdown headers, no commentary.
   If there are no genuine insights worth persisting, output nothing at all." \
  2>"$STDERR_FILE")
RC=$?
set -e
log "claude rc=$RC learnings_bytes=${#LEARNINGS}"
if [ -n "${CLAUDE_HOOK_DEBUG:-}" ]; then
  if [ -s "$STDERR_FILE" ]; then
    log "claude stderr: $(tr '\n' ' ' < "$STDERR_FILE" | cut -c1-500)"
  fi
  if [ "$RC" -ne 0 ] && [ -n "$LEARNINGS" ]; then
    log "claude stdout (preview): $(printf '%s' "$LEARNINGS" | tr '\n' ' ' | cut -c1-500)"
  fi
fi
rm -f "$STDERR_FILE"

# Only persist when the call actually succeeded. On non-zero rc, the CLI
# writes its error to stdout (e.g. "Prompt is too long"), which we must
# NOT append to the memory file.
if [ "$RC" -ne 0 ]; then
  log "claude failed (rc=$RC); not writing"
  exit 0
fi

# Reject obvious non-bullet output. Any line we keep must start with "- [".
LEARNINGS=$(printf '%s\n' "$LEARNINGS" | grep -E '^- \[' || true)

if [ -n "$LEARNINGS" ]; then
  {
    echo ""
    echo "<!-- Session: $TIMESTAMP -->"
    echo "$LEARNINGS"
  } >> "$MEMORY_FILE"
  log "wrote learnings to $MEMORY_FILE"
else
  log "no bullet lines in output; not writing"
fi
